# frozen_string_literal: true

class LoggingInfrastructure::PerformanceMonitor # rubocop:disable Metrics/ClassLength

  SLOW_QUERY_THRESHOLD = 100 # ms
  SLOW_API_THRESHOLD = 1000 # ms
  HIGH_MEMORY_THRESHOLD = 500 # MB

  class << self

    def track_database_query(sql, name, duration_ms, connection_info = {})
      return if sql.blank? || excluded_query?(sql)

      metadata = {
        metric_type: 'database_query',
        metric_data: {
          sql: sanitize_sql(sql),
          name:,
          duration_ms: duration_ms.round(2),
          slow: duration_ms > SLOW_QUERY_THRESHOLD,
          connection_pool: extract_connection_pool_stats,
          table: extract_table_name(sql),
          operation: extract_operation(sql),
          **connection_info,
        },
      }

      log_level = duration_ms > SLOW_QUERY_THRESHOLD ? :warn : :debug
      logger.public_send(log_level, 'Database query executed', metadata)
    end

    def track_cache_operation(operation, key, hit, duration_ms)
      metadata = {
        metric_type: 'cache_operation',
        metric_data: {
          operation: operation.to_s,
          key: sanitize_cache_key(key),
          hit:,
          duration_ms: duration_ms.round(2),
          cache_store: Rails.cache.class.name,
        },
      }

      logger.debug('Cache operation performed', metadata)
      update_cache_stats(hit)
    end

    def track_external_api_call(url, method, duration_ms, status, options = {})
      metadata = {
        metric_type: 'external_api_call',
        metric_data: {
          url: sanitize_url(url),
          method: method.to_s.upcase,
          duration_ms: duration_ms.round(2),
          status:,
          slow: duration_ms > SLOW_API_THRESHOLD,
          host: extract_host(url),
        },
      }

      metadata[:metric_data][:request_size] = options[:request_body].bytesize if options[:request_body]
      metadata[:metric_data][:response_size] = options[:response_body].bytesize if options[:response_body]

      log_level = duration_ms > SLOW_API_THRESHOLD ? :warn : :info
      logger.public_send(log_level, 'External API call completed', metadata)
    end

    def track_memory_usage
      memory_mb = get_memory_usage_mb
      gc_stats = GC.stat

      metadata = {
        metric_type: 'memory_usage',
        metric_data: {
          usage_mb: memory_mb.round(2),
          high_usage: memory_mb > HIGH_MEMORY_THRESHOLD,
          gc_count: gc_stats[:count],
          gc_time: gc_stats[:time],
          heap_slots: gc_stats[:heap_allocated_slots],
          heap_free_slots: gc_stats[:heap_free_slots],
        },
      }

      log_level = memory_mb > HIGH_MEMORY_THRESHOLD ? :warn : :debug
      logger.public_send(log_level, 'Memory usage tracked', metadata)
    end

    def track_job_performance(job_class, duration_ms, status, error = nil)
      metadata = {
        metric_type: 'background_job',
        metric_data: {
          job_class: job_class.to_s,
          duration_ms: duration_ms.round(2),
          status: status.to_s,
          memory_before_mb: @memory_before&.round(2),
          memory_after_mb: get_memory_usage_mb.round(2),
        },
      }

      if error
        metadata[:metric_data][:error] = {
          class: error.class.name,
          message: error.message,
        }
      end

      log_level = error ? :error : :info
      logger.public_send(log_level, 'Background job completed', metadata)
    end

    def start_tracking
      @memory_before = get_memory_usage_mb
      @start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def end_tracking
      return unless @start_time

      duration_ms = ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - @start_time) * 1000).round(2)
      @start_time = nil
      duration_ms
    end

    private

    def logger
      @logger ||= if defined?(Rails) && Rails.respond_to?(:logger) && Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
                    Rails.logger
                  else
                    LoggingInfrastructure::StructuredLogger.new
                  end
    end

    attr_writer :logger

    def excluded_query?(sql)
      sql.match?(/\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE SAVEPOINT)/i) ||
        sql.match?(/schema_migrations/) ||
        sql.match?(/ar_internal_metadata/)
    end

    def sanitize_sql(sql)
      # Remove sensitive values but keep the structure
      sql.gsub(/\b\d{4,}\b/, '[ID]')
        .gsub(/'[^']*'/, "'[VALUE]'")
        .gsub(/"[^"]*"/, '"[VALUE]"')
        .squish
        .truncate(500)
    end

    def extract_table_name(sql)
      patterns = [
        /FROM\s+["'`]?(\w+)["'`]?/i,
        /INSERT\s+INTO\s+["'`]?(\w+)["'`]?/i,
        /UPDATE\s+["'`]?(\w+)["'`]?/i,
        /DELETE\s+FROM\s+["'`]?(\w+)["'`]?/i,
      ]

      patterns.each do |pattern|
        match = sql.match(pattern)
        return match[1] if match
      end

      'unknown'
    end

    def extract_operation(sql)
      operations = {
        'SELECT' => 'select',
        'INSERT' => 'insert',
        'UPDATE' => 'update',
        'DELETE' => 'delete',
        'CREATE' => 'create',
        'DROP' => 'drop',
        'ALTER' => 'alter',
      }

      sql_upper = sql.upcase
      operations.each do |keyword, operation|
        return operation if sql_upper.start_with?(keyword)
      end

      'other'
    end

    def extract_connection_pool_stats
      return {} unless defined?(ActiveRecord::Base)

      pool = ActiveRecord::Base.connection_pool
      {
        size: pool.size,
        connections: pool.connections.size,
        busy: pool.connections.count(&:in_use?),
        dead: pool.connections.count(&:dead?),
        idle: pool.connections.count { |c| !c.in_use? && !c.dead? },
        waiting: pool.num_waiting_in_queue,
      }
    rescue StandardError
      {}
    end

    def sanitize_cache_key(key)
      return '[FILTERED]' if key.to_s.match?(/password|token|secret/i)

      key.to_s.truncate(100)
    end

    def update_cache_stats(hit)
      Thread.current[:cache_hits] ||= 0
      Thread.current[:cache_misses] ||= 0

      if hit
        Thread.current[:cache_hits] += 1
      else
        Thread.current[:cache_misses] += 1
      end
    end

    def sanitize_url(url)
      uri = URI.parse(url.to_s)
      # Remove sensitive query parameters
      if uri.query
        params = CGI.parse(uri.query)
        sanitized_params = []
        params.each do |key, values|
          if key.match?(/password|token|key|secret/i)
            sanitized_params << "#{key}=[FILTERED]"
          else
            values.each do |value|
              sanitized_params << "#{key}=#{CGI.escape(value)}"
            end
          end
        end
        uri.query = sanitized_params.join('&')
      end
      uri.to_s
    rescue URI::InvalidURIError
      '[INVALID_URL]'
    end

    def extract_host(url)
      URI.parse(url.to_s).host
    rescue URI::InvalidURIError
      'unknown'
    end

    def get_memory_usage_mb # rubocop:disable Naming/AccessorMethodName
      if File.exist?("/proc/#{Process.pid}/statm")
        File.read("/proc/#{Process.pid}/statm").split[0].to_i * 4096 / 1024.0 / 1024.0
      elsif defined?(GetProcessMem)
        GetProcessMem.new.mb
      elsif defined?(ObjectSpace)
        # Fallback to ObjectSpace if available
        ObjectSpace.memsize_of_all / 1024.0 / 1024.0
      else
        0
      end
    rescue StandardError
      0
    end

  end

end
