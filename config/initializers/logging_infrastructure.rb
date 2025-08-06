# frozen_string_literal: true

require_relative '../../app/lib/logging_infrastructure'
require_relative '../../app/lib/logging_infrastructure/structured_logger'
require_relative '../../app/lib/logging_infrastructure/correlation_id'
require_relative '../../app/lib/logging_infrastructure/request_middleware'
require_relative '../../app/lib/logging_infrastructure/performance_monitor'
require_relative '../../app/lib/logging_infrastructure/error_handler'
require_relative '../../app/lib/logging_infrastructure/database_logger'
require_relative '../../app/lib/logging_infrastructure/job_logger'

Rails.application.configure do
  # Configure log level based on environment
  log_level = case Rails.env
              when 'production'
                ENV.fetch('LOG_LEVEL', 'info').to_sym
              when 'development'
                :debug
              when 'test'
                ENV['DEBUG'] ? :debug : :warn
              else
                :info
              end

  # Configure log outputs
  log_outputs = []

  # File output with rotation
  if Rails.env.production? || ENV['LOG_TO_FILE']
    log_dir = Rails.root.join('log')
    FileUtils.mkdir_p(log_dir) unless File.directory?(log_dir)
    
    log_file = File.open(
      log_dir.join("#{Rails.env}.log"),
      File::WRONLY | File::APPEND | File::CREAT
    )
    
    # Configure log rotation
    if Rails.env.production?
      require 'logger'
      log_file = Logger::LogDevice.new(
        log_dir.join("#{Rails.env}.log"),
        shift_age: 'daily',     # Rotate daily
        shift_size: 100 * 1024 * 1024, # Or when file reaches 100MB
        shift_period_suffix: '%Y%m%d'
      )
    end
    
    log_outputs << log_file
  end

  # STDOUT output for containers, development and test
  if Rails.env.development? || Rails.env.test? || ENV['LOG_TO_STDOUT']
    log_outputs << $stdout
  end

  # Use STDOUT in production for container compatibility
  if Rails.env.production? && !ENV['LOG_TO_FILE_ONLY']
    log_outputs << $stdout
  end

  # Create structured logger
  if log_outputs.any?
    # For now, use single output to avoid BroadcastLogger compatibility issues
    # TODO: Implement custom broadcast logger for structured logging
    config.logger = LoggingInfrastructure::StructuredLogger.new(
      level: log_level,
      output: log_outputs.first
    )
  end

  # Configure Rails log tags
  config.log_tags = [:request_id, -> (req) { 
    LoggingInfrastructure::CorrelationId.extract_from_headers(req.headers) 
  }]

  # Disable default Rails request logging (we'll use our middleware)
  config.rails_semantic_logger.started = false if defined?(SemanticLogger)
  config.rails_semantic_logger.rendered = false if defined?(SemanticLogger)
  
  # Configure ActiveRecord logging
  if defined?(ActiveRecord)
    ActiveRecord::Base.logger = config.logger
    # verbose_query_logs is not available in Rails 8
    # ActiveRecord::Base.verbose_query_logs = Rails.env.development?
  end

  # Configure ActionView logging
  if defined?(ActionView)
    ActionView::Base.logger = config.logger
  end

  # Configure ActionMailer logging
  if defined?(ActionMailer)
    ActionMailer::Base.logger = config.logger
  end

  # Configure ActiveJob logging
  if defined?(ActiveJob)
    ActiveJob::Base.logger = config.logger
  end

  # Filter sensitive parameters
  config.filter_parameters += %i[
    password password_confirmation token api_key
    secret access_token refresh_token authorization
    cookie session credit_card card_number cvv ssn
  ]
end

# Install middleware
Rails.application.config.middleware.insert_after ActionDispatch::RequestId,
  LoggingInfrastructure::RequestMiddleware,
  logger: Rails.logger

# Install database logger
LoggingInfrastructure::DatabaseLogger.install if defined?(ActiveRecord)

# Include job logger in ApplicationJob
Rails.application.config.after_initialize do
  if defined?(ApplicationJob)
    ApplicationJob.class_eval do
      include LoggingInfrastructure::JobLogger
    end
  end

  # Configure global exception handling
  if defined?(ActionController::Base)
    ActionController::Base.class_eval do
      rescue_from StandardError do |exception|
        LoggingInfrastructure::ErrorHandler.handle_exception(exception, {
          controller: controller_name,
          action: action_name,
          params: filtered_params,
          url: request.url,
          method: request.method,
          ip: request.remote_ip,
          user_agent: request.user_agent
        })

        # Re-raise for proper error handling
        raise exception
      end

      private

      def filtered_params
        params.to_unsafe_h.except(:controller, :action)
      rescue StandardError
        {}
      end
    end
  end

  # Log application startup
  if Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
    Rails.logger.info("Application started", {
      event: 'application_started',
      rails_version: Rails.version,
      ruby_version: RUBY_VERSION,
      environment: Rails.env,
      pid: Process.pid,
      hostname: Socket.gethostname,
      config: {
        database: ActiveRecord::Base.connection.current_database,
        cache_store: Rails.cache.class.name,
        job_queue_adapter: ActiveJob::Base.queue_adapter.class.name
      }
    })
  elsif Rails.logger.respond_to?(:info)
    Rails.logger.info("Application started - Rails #{Rails.version}, Ruby #{RUBY_VERSION}")
  end
end

# Add helper methods to Rails
module Rails
  def self.structured_logger
    logger.is_a?(LoggingInfrastructure::StructuredLogger) ? logger : nil
  end
end