# frozen_string_literal: true

class LoggingInfrastructure::RequestMiddleware

  EXCLUDED_PATHS = %w[/health /readiness /favicon.ico /assets].freeze
  EXCLUDED_PARAMS = %w[controller action format].freeze

  def initialize(app, logger: nil)
    @app = app
    @logger = logger || LoggingInfrastructure::StructuredLogger.new(output: $stdout)
  end

  def call(env)
    return @app.call(env) if excluded_path?(env['PATH_INFO'])

    request = ActionDispatch::Request.new(env)
    correlation_id = generate_or_extract_correlation_id(request)
    LoggingInfrastructure::CorrelationId.set(correlation_id)

    set_request_context(request)
    start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC)

    log_request_start(request, correlation_id)

    status, headers, response = @app.call(env)
    headers['X-Correlation-ID'] = correlation_id

    duration = calculate_duration(start_time)
    log_request_end(request, status, duration, response)

    [status, headers, response]
  rescue StandardError => e
    duration = calculate_duration(start_time)
    log_request_error(request, e, duration)
    raise
  ensure
    clear_request_context
  end

  private

  def excluded_path?(path)
    EXCLUDED_PATHS.any? { |excluded| path.start_with?(excluded) }
  end

  def generate_or_extract_correlation_id(request)
    existing_id = LoggingInfrastructure::CorrelationId.extract_from_headers(request.headers)
    existing_id || LoggingInfrastructure::CorrelationId.generate
  end

  def set_request_context(request) # rubocop:disable Naming/AccessorMethodName
    Thread.current[:request_id] = request.request_id
    Thread.current[:session_id] = request.session&.id if request.session.respond_to?(:id)
    Thread.current[:current_user_id] = extract_user_id(request)
    Thread.current[:request_path] = request.path
    Thread.current[:request_method] = request.request_method
    Thread.current[:remote_ip] = request.remote_ip
  end

  def clear_request_context
    Thread.current[:request_id] = nil
    Thread.current[:session_id] = nil
    Thread.current[:current_user_id] = nil
    Thread.current[:request_path] = nil
    Thread.current[:request_method] = nil
    Thread.current[:remote_ip] = nil
    LoggingInfrastructure::CorrelationId.reset
  end

  def extract_user_id(request)
    # Try to extract user_id from session or warden
    if request.session[:user_id]
      request.session[:user_id]
    elsif request.env['warden']&.user(:user)
      request.env['warden'].user(:user).id
    elsif request.env['warden']&.user(:admin)
      "admin_#{request.env['warden'].user(:admin).id}"
    end
  end

  def calculate_duration(start_time)
    return 0 unless start_time

    ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - start_time) * 1000).round(2)
  end

  def log_request_start(request, correlation_id)
    metadata = extract_request_metadata(request).merge(
      event: 'request_started',
      correlation_id:
    )
    # Use the appropriate method based on logger type
    if @logger.is_a?(LoggingInfrastructure::StructuredLogger)
      @logger.info('Request started', metadata)
    elsif @logger.respond_to?(:info)
      @logger.info("Request started: #{metadata.to_json}")
    end
  end

  def log_request_end(request, status, duration, response)
    response_size = calculate_response_size(response)
    metadata = extract_request_metadata(request).merge(
      event: 'request_completed',
      response: {
        status:,
        duration_ms: duration,
        size_bytes: response_size,
      },
      database: extract_database_metrics,
      memory: extract_memory_metrics
    )
    # Use the appropriate method based on logger type
    if @logger.is_a?(LoggingInfrastructure::StructuredLogger)
      @logger.info('Request completed', metadata)
    elsif @logger.respond_to?(:info)
      @logger.info("Request completed: #{metadata.to_json}")
    end
  end

  def log_request_error(request, exception, duration)
    metadata = extract_request_metadata(request).merge(
      event: 'request_failed',
      error: {
        class: exception.class.name,
        message: exception.message,
        backtrace: exception.backtrace&.first(5),
      },
      duration_ms: duration
    )
    # Use the appropriate method based on logger type
    if @logger.is_a?(LoggingInfrastructure::StructuredLogger)
      @logger.error('Request failed', metadata)
    elsif @logger.respond_to?(:error)
      @logger.error("Request failed: #{metadata.to_json}")
    end
  end

  def extract_request_metadata(request)
    {
      request: {
        method: request.request_method,
        path: request.path,
        url: request.url,
        ip: request.remote_ip,
        user_agent: request.user_agent,
        referer: request.referer,
        params: filter_params(request.params),
        headers: extract_relevant_headers(request),
      },
    }
  end

  def filter_params(params)
    return {} unless params.is_a?(Hash)

    params.except(*EXCLUDED_PARAMS).tap do |filtered|
      if Rails.application.config.filter_parameters.any?
        parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
        parameter_filter.filter(filtered)
      end
    end
  end

  def extract_relevant_headers(request)
    relevant_headers = {}
    %w[Accept Accept-Language Content-Type].each do |header|
      key = "HTTP_#{header.upcase.gsub('-', '_')}"
      relevant_headers[header] = request.env[key] if request.env[key]
    end
    relevant_headers
  end

  def calculate_response_size(response)
    # Response here is the body part of the Rack response tuple
    case response
    when Array
      response.sum { |part| part.respond_to?(:bytesize) ? part.bytesize : part.to_s.bytesize }
    when String
      response.bytesize
    else
      # Try to get body if it's a response object
      if response.respond_to?(:body)
        calculate_response_size(response.body)
      else
        0
      end
    end
  rescue StandardError
    0
  end

  def extract_database_metrics
    if defined?(ActiveRecord::Base) && ActiveRecord::Base.connected?
      runtime = ActiveRecord::RuntimeRegistry.sql_runtime || 0
      {
        query_count: ActiveRecord::RuntimeRegistry.sql_runtime_count || 0,
        total_duration_ms: runtime.round(2),
      }
    else
      {}
    end
  rescue StandardError
    {}
  end

  def extract_memory_metrics
    if defined?(GC)
      gc_stat = GC.stat
      {
        usage_mb: (get_memory_usage / 1024.0 / 1024.0).round(2),
        gc_count: gc_stat[:count],
        gc_time: gc_stat[:time],
      }
    else
      {}
    end
  rescue StandardError
    {}
  end

  def get_memory_usage # rubocop:disable Naming/AccessorMethodName
    if File.exist?("/proc/#{Process.pid}/statm")
      File.read("/proc/#{Process.pid}/statm").split[0].to_i * 4096
    else
      0
    end
  rescue StandardError
    0
  end

end
