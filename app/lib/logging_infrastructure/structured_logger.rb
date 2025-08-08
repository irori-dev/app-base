# frozen_string_literal: true

require 'logger'

class LoggingInfrastructure::StructuredLogger

  SENSITIVE_KEYS = %w[
    password password_confirmation token api_key secret
    access_token refresh_token authorization cookie session
    credit_card card_number cvv ssn
  ].freeze

  SENSITIVE_PATTERNS = [
    /password/i,
    /token/i,
    /api[-_]?key/i,
    /secret/i,
    /authorization/i,
    /cookie/i,
    /credit[-_]?card/i,
    /\bssn\b/i,
    /\bcvv\b/i,
  ].freeze

  attr_reader :level, :output

  def initialize(level: :info, output: $stdout)
    @level = level
    @output = output
    @log_levels = { debug: 0, info: 1, warn: 2, error: 3, fatal: 4 }
    @current_level = @log_levels[level] || 1
  end

  def debug(message = nil, metadata = {}, &block)
    return unless debug?

    message = block.call if block_given? && message.nil?
    log(:debug, message || '', metadata)
  end

  def info(message = nil, metadata = {}, &block)
    return unless info?

    message = block.call if block_given? && message.nil?
    log(:info, message || '', metadata)
  end

  def warn(message = nil, metadata = {}, &block)
    return unless warn?

    message = block.call if block_given? && message.nil?
    log(:warn, message || '', metadata)
  end

  def error(message = nil, metadata = {}, &block)
    return unless error?

    message = block.call if block_given? && message.nil?
    log(:error, message || '', metadata)
  end

  def fatal(message = nil, metadata = {}, &block)
    return unless fatal?

    message = block.call if block_given? && message.nil?
    log(:fatal, message || '', metadata)
  end

  # Rails logger compatibility methods
  def debug?
    @log_levels[:debug] >= @current_level
  end

  def info?
    @log_levels[:info] >= @current_level
  end

  def warn?
    @log_levels[:warn] >= @current_level
  end

  def error?
    @log_levels[:error] >= @current_level
  end

  def fatal?
    @log_levels[:fatal] >= @current_level
  end

  # Rails logger compatibility - silence method
  def silence(temporary_level = :error)
    old_level = @level
    @level = temporary_level
    @current_level = @log_levels[temporary_level] || @log_levels[:error]
    yield self
  ensure
    @level = old_level
    @current_level = @log_levels[old_level] || 1
  end

  # Rails logger compatibility - unknown method
  def unknown(message = nil, progname = nil, &block)
    message = progname if message.nil? && progname
    message = block.call if message.nil? && block_given?
    log(:fatal, message || 'Unknown', {})
  end

  # Rails logger compatibility - add method
  def add(severity, message = nil, progname = nil, &block)
    severity_level = severity_to_level(severity)
    message = progname if message.nil? && progname
    message = block.call if message.nil? && block_given?
    log(severity_level, message || '', {})
  end

  # Rails logger compatibility - formatter
  attr_accessor :formatter

  # Rails logger compatibility - close method
  def close
    @output.close if @output.respond_to?(:close) && @output != $stdout && @output != $stderr
  end

  SEVERITY_MAPPING = {
    Logger::DEBUG => :debug,
    Logger::INFO => :info,
    Logger::WARN => :warn,
    Logger::ERROR => :error,
    Logger::FATAL => :fatal,
    Logger::UNKNOWN => :fatal,
  }.freeze
  private_constant :SEVERITY_MAPPING

  private

  def severity_to_level(severity)
    SEVERITY_MAPPING[severity] || :info
  end

  def log(level, message, metadata)
    return if @log_levels[level] < @current_level

    log_entry = format_log(level, message, metadata)
    output.puts(log_entry.to_json)
    output.flush
  end

  def format_log(level, message, metadata)
    {
      timestamp: Time.current.iso8601(3),
      level: level.to_s,
      message:,
      correlation_id: Thread.current[:correlation_id],
      user_id: Thread.current[:current_user_id],
      session_id: Thread.current[:session_id],
      environment: Rails.env,
      service: Rails.application.class.module_parent_name.underscore,
      version: Rails.application.config.respond_to?(:version) ? Rails.application.config.version : '1.0.0',
      hostname: Socket.gethostname,
      pid: Process.pid,
      thread_id: Thread.current.object_id,
      **filter_sensitive_data(metadata),
    }.compact
  end

  def filter_sensitive_data(data)
    return data unless data.is_a?(Hash)

    data.deep_dup.tap do |filtered|
      filter_hash!(filtered)
    end
  end

  def filter_hash!(hash)
    hash.each do |key, value|
      hash[key] = filter_value(key, value)
    end
  end

  def filter_value(key, value)
    return '[FILTERED]' if sensitive_key?(key)
    return filter_hash!(value) if value.is_a?(Hash)
    return filter_array(value) if value.is_a?(Array)
    # Don't filter fingerprints - they're meant for error grouping
    return value if key.to_s == 'fingerprint'
    return '[FILTERED]' if value.is_a?(String) && looks_like_sensitive_value?(value)

    value
  end

  def filter_array(array)
    array.each { |item| filter_hash!(item) if item.is_a?(Hash) }
    array
  end

  def sensitive_key?(key)
    key_str = key.to_s.downcase
    SENSITIVE_KEYS.include?(key_str) || SENSITIVE_PATTERNS.any? { |pattern| key_str.match?(pattern) }
  end

  def looks_like_sensitive_value?(value)
    return false unless value.is_a?(String)
    return false if value.length < 8

    # Check for common token patterns
    looks_like_bearer_token?(value) ||
      looks_like_hash?(value) ||
      looks_like_base64?(value) ||
      looks_like_api_key?(value)
  end

  def looks_like_bearer_token?(value)
    value.match?(/^Bearer\s+/i)
  end

  def looks_like_hash?(value)
    value.match?(/^[a-f0-9]{32,}$/i) # MD5, SHA hashes
  end

  def looks_like_base64?(value)
    value.match?(%r{^[A-Za-z0-9+/]{20,}={0,2}$})
  end

  def looks_like_api_key?(value)
    value.match?(/^sk_[a-zA-Z0-9]{24,}$/) || # Stripe secret key
      value.match?(/^pk_[a-zA-Z0-9]{24,}$/) || # Stripe public key
      value.match?(/^[A-Z0-9]{20,}$/) # AWS keys
  end

end
