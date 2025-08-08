# frozen_string_literal: true

class LoggingInfrastructure::DatabaseLogger # rubocop:disable Metrics/ClassLength

  class << self

    def install
      return if @installed

      install_active_record_logger if defined?(ActiveRecord)
      @installed = true
    end

    private

    def install_active_record_logger
      # Subscribe to SQL notifications
      ActiveSupport::Notifications.subscribe('sql.active_record') do |name, start, finish, id, payload|
        handle_sql_notification(name, start, finish, id, payload)
      end

      # Monitor connection pool
      install_connection_pool_monitor

      # Install query count tracking
      install_query_counter
    end

    def handle_sql_notification(_name, start, finish, _id, payload)
      return if skip_query?(payload)

      duration_ms = (finish - start) * 1000
      sql = payload[:sql]
      query_name = payload[:name] || 'SQL'
      payload[:binds]
      payload[:type_casted_binds]
      cached = payload[:cached] || false

      connection_info = extract_connection_info(payload)

      # Track the query
      LoggingInfrastructure::PerformanceMonitor.track_database_query(
        sql,
        query_name,
        duration_ms,
        connection_info.merge(
          cached:,
          transaction_id: current_transaction_id,
          statement_name: payload[:statement_name]
        )
      )

      # Update thread-local query stats
      update_query_stats(duration_ms, cached)

      # Check for N+1 queries
      detect_n_plus_one(sql, query_name) if Rails.env.development?
    end

    def skip_query?(payload)
      # Skip internal Rails queries
      payload[:name] == 'SCHEMA' ||
        payload[:sql].match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i) ||
        payload[:sql].match?(/pg_/) ||
        payload[:sql].match?(/information_schema/) ||
        payload[:sql].match?(/\$\d+/) || # Skip prepared statement placeholders
        # Skip Solid Queue internal queries in worker processes
        (Thread.current[:solid_queue_worker] && payload[:sql].match?(/solid_queue/i))
    end

    def extract_connection_info(payload)
      connection = payload[:connection]
      return {} unless connection

      {
        database: connection.current_database,
        adapter: connection.adapter_name,
        pool_id: connection.pool.object_id,
      }
    rescue StandardError
      {}
    end

    def current_transaction_id
      # Try to get the current transaction ID if in a transaction
      if defined?(ActiveRecord::Base) && ActiveRecord::Base.connection.transaction_open?
        ActiveRecord::Base.connection.current_transaction.object_id
      end
    rescue StandardError
      nil
    end

    def update_query_stats(duration_ms, cached)
      Thread.current[:db_query_count] ||= 0
      Thread.current[:db_query_count] += 1

      Thread.current[:db_query_time] ||= 0
      Thread.current[:db_query_time] += duration_ms

      if cached
        Thread.current[:db_cached_query_count] ||= 0
        Thread.current[:db_cached_query_count] += 1
      end

      # Track slow queries
      return unless duration_ms > LoggingInfrastructure::PerformanceMonitor::SLOW_QUERY_THRESHOLD

      Thread.current[:slow_query_count] ||= 0
      Thread.current[:slow_query_count] += 1
    end

    def detect_n_plus_one(sql, name)
      return unless sql.match?(/SELECT/i)

      # Skip N+1 detection for Solid Queue tables
      return if sql.match?(/solid_queue|solid_cache|solid_cable/i)

      # Skip N+1 detection in background jobs (they often need to loop through records)
      return if Thread.current[:solid_queue_worker]

      # Simple N+1 detection based on repeated similar queries
      @query_patterns ||= Hash.new(0)
      pattern = generate_query_pattern(sql)

      @query_patterns[pattern] += 1

      if @query_patterns[pattern] > 5
        logger.warn('Potential N+1 query detected', {
          pattern:,
          count: @query_patterns[pattern],
          sql: sql.truncate(200),
          name:,
        })
      end

      # Clean up old patterns periodically
      @query_patterns.clear if @query_patterns.size > 100
    end

    def generate_query_pattern(sql)
      # Generate a pattern by removing specific values
      sql.gsub(/\b\d+\b/, 'N')
        .gsub(/'[^']*'/, "'?'")
        .gsub(/"[^"]*"/, '"?"')
        .gsub(/\([^)]*\)/, '(?)')
        .squish
    end

    def install_connection_pool_monitor
      return unless defined?(ActiveRecord::Base)

      # Periodic connection pool monitoring
      Thread.new do
        loop do
          sleep 30 # Check every 30 seconds
          monitor_connection_pools
        rescue StandardError => e
          logger.error('Connection pool monitoring error', error: e.message)
        end
      end
    end

    def monitor_connection_pools
      ActiveRecord::Base.connection_handler.connection_pool_list.each do |pool|
        stats = build_pool_stats(pool)
        log_pool_status(stats)
      end
    end

    def build_pool_stats(pool)
      {
        spec_name: extract_pool_name(pool),
        size: pool.size,
        connections: pool.connections.size,
        busy: pool.connections.count(&:in_use?),
        dead: pool.connections.count(&:dead?),
        idle: pool.connections.count { |c| !c.in_use? && !c.dead? },
        waiting: pool.num_waiting_in_queue,
        checkout_timeout: pool.checkout_timeout,
      }
    rescue StandardError => e
      build_pool_error_stats(pool, e)
    end

    def extract_pool_name(pool)
      return pool.spec.name if pool.respond_to?(:spec)
      return pool.connection_name if pool.respond_to?(:connection_name)
      return pool.db_config.name if pool.respond_to?(:db_config)

      'unknown'
    end

    def build_pool_error_stats(pool, error)
      {
        error: error.message,
        spec_name: 'error',
        size: pool.respond_to?(:size) ? pool.size : 0,
        connections: pool.respond_to?(:connections) ? pool.connections.size : 0,
      }
    end

    def log_pool_status(stats)
      # Skip if error occurred
      return if stats[:error]

      waiting = stats[:waiting] || 0
      dead = stats[:dead] || 0

      if waiting.positive? || dead.positive?
        logger.warn('Connection pool issues detected', {
          metric_type: 'connection_pool',
          pool_stats: stats,
        })
      else
        logger.debug('Connection pool status', {
          metric_type: 'connection_pool',
          pool_stats: stats,
        })
      end
    end

    def install_query_counter # rubocop:disable Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
      # Add query counting to ActiveRecord
      ActiveSupport.on_load(:active_record) do # rubocop:disable Metrics/BlockLength
        ActiveRecord::RuntimeRegistry.class_eval do
          attr_accessor :sql_runtime_count

          def self.sql_runtime_count
            ActiveSupport::IsolatedExecutionState[:active_record_sql_runtime_count] ||= 0
          end

          def self.sql_runtime_count=(value)
            ActiveSupport::IsolatedExecutionState[:active_record_sql_runtime_count] = value
          end

          def self.reset_runtime
            rt = sql_runtime
            self.sql_runtime = 0
            self.sql_runtime_count = 0
            rt
          end
        end

        # Patch log subscriber to count queries
        ActiveRecord::LogSubscriber.class_eval do
          alias_method :original_sql, :sql

          def sql(event)
            ActiveRecord::RuntimeRegistry.sql_runtime_count += 1 unless event.payload[:cached]

            # Skip default SQL logging for Solid Queue processes and internal queries
            # This prevents duplicate/verbose logging in background jobs
            return unless should_log_sql?(event)

            original_sql(event)
          end

          private

          def should_log_sql?(event)
            # Skip logging for Solid Queue internal queries
            return false if event.payload[:sql]&.match?(/solid_queue|solid_cache|solid_cable/)

            # Skip logging in Solid Queue worker processes (they have their own logging)
            return false if Thread.current[:solid_queue_worker]

            # Skip if we're running in a Solid Queue process
            return false if $PROGRAM_NAME =~ /solid_queue/

            # Skip if we're using structured logger (to avoid duplicate logs)
            # We're already logging via our own handler
            return false if Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)

            # Only allow default logging if not using our structured logger
            !Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
          end
        end
      end
    end

    def logger
      @logger ||= if defined?(Rails.logger) && Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
                    Rails.logger
                  else
                    LoggingInfrastructure::StructuredLogger.new
                  end
    end

  end

end
