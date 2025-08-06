# frozen_string_literal: true

module LoggingInfrastructure::JobLogger # rubocop:disable Metrics/ModuleLength

  extend ActiveSupport::Concern

  included do
    around_perform :log_job_execution
    before_enqueue :log_job_enqueue
    after_enqueue :log_job_enqueued
    # on_discard and on_retry are not available in Rails 8
    # Use rescue_from instead
    rescue_from StandardError do |exception|
      log_job_error(exception)
      raise exception
    end
  end

  private

  def log_job_execution
    # Inherit correlation ID from enqueue time
    correlation_id = @correlation_id || LoggingInfrastructure::CorrelationId.generate
    LoggingInfrastructure::CorrelationId.set(correlation_id)

    # Set job context
    set_job_context

    # Track performance
    LoggingInfrastructure::PerformanceMonitor.start_tracking
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    log_job_start

    yield

    duration_ms = calculate_duration(start_time)
    LoggingInfrastructure::PerformanceMonitor.track_job_performance(self.class.name, duration_ms, :success)
    log_job_success(duration_ms)
  rescue StandardError => e
    duration_ms = calculate_duration(start_time)
    LoggingInfrastructure::PerformanceMonitor.track_job_performance(self.class.name, duration_ms, :failed, e)
    log_job_failure(duration_ms, e)

    # Re-raise the error for proper job handling
    raise
  ensure
    clear_job_context
  end

  def log_job_enqueue
    # Store correlation ID and metadata for later use
    @correlation_id = LoggingInfrastructure::CorrelationId.current || LoggingInfrastructure::CorrelationId.generate
    @enqueued_by_user_id = Thread.current[:current_user_id]
    @enqueued_from_request = Thread.current[:request_id]
  end

  def log_job_enqueued
    logger.info('Job enqueued', {
      event: 'job_enqueued',
      job: {
        class: self.class.name,
        id: job_id,
        queue: queue_name,
        priority: priority,
        arguments: sanitized_arguments,
        scheduled_at: scheduled_at,
        correlation_id: @correlation_id,
        enqueued_by: @enqueued_by_user_id,
        request_id: @enqueued_from_request,
      },
    })
  end

  def log_job_start
    logger.info('Job started', {
      event: 'job_started',
      job: {
        class: self.class.name,
        id: job_id,
        queue: queue_name,
        arguments: sanitized_arguments,
        attempt_number: executions,
        correlation_id: LoggingInfrastructure::CorrelationId.current,
      },
    })
  end

  def log_job_success(duration_ms)
    logger.info('Job completed successfully', {
      event: 'job_completed',
      job: {
        class: self.class.name,
        id: job_id,
        queue: queue_name,
        duration_ms:,
        attempt_number: executions,
        correlation_id: LoggingInfrastructure::CorrelationId.current,
      },
      performance: extract_performance_metrics,
    })
  end

  def log_job_failure(duration_ms, exception)
    logger.error('Job failed', {
      event: 'job_failed',
      job: {
        class: self.class.name,
        id: job_id,
        queue: queue_name,
        duration_ms:,
        attempt_number: executions,
        correlation_id: LoggingInfrastructure::CorrelationId.current,
      },
      error: {
        class: exception.class.name,
        message: exception.message,
        backtrace: clean_backtrace(exception.backtrace),
      },
    })

    # Send Slack notification for critical job failures
    notify_job_failure(exception) if critical_job?
  end

  def log_job_error(error)
    # Log error for retry or discard
    logger.error('Job error occurred', {
      event: 'job_error',
      job: {
        class: self.class.name,
        id: job_id,
        queue: queue_name,
        attempts: executions,
        correlation_id: @correlation_id,
      },
      error: {
        class: error.class.name,
        message: error.message,
        backtrace: clean_backtrace(error.backtrace),
      },
    })
  end

  def set_job_context
    Thread.current[:job_class] = self.class.name
    Thread.current[:job_id] = job_id
    Thread.current[:job_queue] = queue_name
    Thread.current[:job_arguments] = sanitized_arguments
  end

  def clear_job_context
    Thread.current[:job_class] = nil
    Thread.current[:job_id] = nil
    Thread.current[:job_queue] = nil
    Thread.current[:job_arguments] = nil
    LoggingInfrastructure::CorrelationId.reset
  end

  def sanitized_arguments
    return {} unless respond_to?(:arguments)

    arguments.map do |arg|
      case arg
      when ActiveRecord::Base
        { class: arg.class.name, id: arg.id }
      when Hash
        sanitize_hash(arg)
      when String
        arg.match?(/password|token|secret|key/i) ? '[FILTERED]' : arg
      else
        arg
      end
    end
  end

  def sanitize_hash(hash)
    hash.transform_values do |value|
      if value.is_a?(String) && value.match?(/password|token|secret|key/i)
        '[FILTERED]'
      elsif value.is_a?(Hash)
        sanitize_hash(value)
      else
        value
      end
    end
  end

  def extract_performance_metrics
    {
      database: {
        query_count: Thread.current[:db_query_count] || 0,
        query_time_ms: (Thread.current[:db_query_time] || 0).round(2),
        slow_queries: Thread.current[:slow_query_count] || 0,
      },
      memory: {
        usage_mb: LoggingInfrastructure::PerformanceMonitor.send(:get_memory_usage_mb).round(2),
      },
    }
  end

  def calculate_duration(start_time)
    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
  end

  def clean_backtrace(backtrace)
    return [] unless backtrace

    if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
      Rails.backtrace_cleaner.clean(backtrace).first(5)
    else
      backtrace.first(5)
    end
  end

  def critical_job?
    # Define which jobs are critical
    critical_jobs = %w[
      PaymentProcessorJob
      EmailDeliveryJob
      DataExportJob
      UserDeletionJob
    ]

    critical_jobs.include?(self.class.name)
  end

  def notify_job_failure(exception)
    return unless Rails.application.credentials.dig(:slack, :webhook_url)

    LoggingInfrastructure::ErrorHandler.handle_exception(exception, {
      job_class: self.class.name,
      job_id:,
      queue: queue_name,
      attempts: executions,
    })
  rescue StandardError => e
    logger.error('Failed to send job failure notification', error: e.message)
  end

  def logger
    @logger ||= if defined?(Rails.logger) && Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
                  Rails.logger
                else
                  LoggingInfrastructure::StructuredLogger.new
                end
  end

  module ClassMethods

    # Allow jobs to be configured with custom logging behavior
    def log_as_critical!
      @critical_job = true
    end

    def critical_job?
      @critical_job || false
    end

  end

end
