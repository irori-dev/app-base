# frozen_string_literal: true

# Configure logging for Solid Queue processes
if defined?(SolidQueue)
  Rails.application.config.after_initialize do
    # Detect if we're running in a Solid Queue worker process
    is_solid_queue_process = $0 =~ /solid_queue/ || 
                            ENV['SOLID_QUEUE_WORKER'] || 
                            ENV['SOLID_QUEUE_IN_BACKGROUND']

    if is_solid_queue_process
      # Configure specific logging for Solid Queue
      Rails.logger.info("Configuring logging for Solid Queue worker process")
      
      # Suppress verbose ActiveRecord logging in worker processes
      if defined?(ActiveRecord::Base)
        # Create a filtered logger for ActiveRecord in workers
        filtered_logger = LoggingInfrastructure::StructuredLogger.new(
          level: :warn,
          output: Rails.logger.instance_variable_get(:@output) || $stdout
        )
        
        # Override ActiveRecord logger
        ActiveRecord::Base.logger = filtered_logger
        
        # Disable SQL query logging for Solid Queue internal queries
        ActiveSupport::Notifications.unsubscribe('sql.active_record') if Rails.env.production?
        
        # Re-subscribe with filtering
        ActiveSupport::Notifications.subscribe('sql.active_record') do |name, start, finish, id, payload|
          # Only log non-Solid Queue queries and important queries
          unless payload[:sql]&.match?(/solid_queue|solid_cache|solid_cable/) ||
                 payload[:name] == 'SCHEMA' ||
                 payload[:sql]&.match?(/^(BEGIN|COMMIT|ROLLBACK|SAVEPOINT)/i)
            
            # Let the DatabaseLogger handle it if it's important
            if payload[:sql] && !payload[:cached]
              duration_ms = (finish - start) * 1000
              
              # Only log slow queries in worker context
              if duration_ms > LoggingInfrastructure::PerformanceMonitor::SLOW_QUERY_THRESHOLD
                Rails.logger.warn("Slow query in job", {
                  sql: payload[:sql].truncate(200),
                  duration_ms: duration_ms.round(2),
                  name: payload[:name]
                })
              end
            end
          end
        end
      end
      
      # Mark thread for worker context
      Thread.current[:solid_queue_worker] = true
    end
  end
  
  # Hook into job execution for better context
  # Note: The actual job logging is handled by LoggingInfrastructure::JobLogger
  # This just sets additional context for Solid Queue specific needs
  ActiveSupport.on_load(:active_job) do
    if defined?(ApplicationJob)
      ApplicationJob.class_eval do
        before_perform do |job|
          # Mark thread as being in a job context
          Thread.current[:solid_queue_worker] = true if job.queue_adapter.class.name.include?('SolidQueue')
        end
        
        after_perform do |job|
          Thread.current[:solid_queue_worker] = nil if job.queue_adapter.class.name.include?('SolidQueue')
        end
      end
    end
  end
end