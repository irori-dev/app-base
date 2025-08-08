# frozen_string_literal: true

require 'digest'

class LoggingInfrastructure::ErrorHandler # rubocop:disable Metrics/ClassLength

  SEVERITY_LEVELS = {
    critical: %w[
      ActiveRecord::ConnectionNotEstablished
      ActiveRecord::StatementInvalid
      Redis::CannotConnectError
      PG::ConnectionBad
      SystemExit
    ],
    high: %w[
      NoMethodError
      NameError
      TypeError
      ArgumentError
      ActiveRecord::RecordNotFound
      ActionController::RoutingError
    ],
    medium: %w[
      ActiveRecord::RecordInvalid
      ActiveRecord::RecordNotSaved
      ActionController::ParameterMissing
      ActionController::UnpermittedParameters
    ],
    low: %w[
      ActiveRecord::StaleObjectError
      ActionController::InvalidAuthenticityToken
    ],
  }.freeze

  SECURITY_EVENTS = {
    authentication_failure: 'Authentication Failed',
    unauthorized_access: 'Unauthorized Access Attempt',
    suspicious_activity: 'Suspicious Activity Detected',
    rate_limit_exceeded: 'Rate Limit Exceeded',
    invalid_token: 'Invalid Token Used',
    permission_denied: 'Permission Denied',
  }.freeze

  class << self

    def handle_exception(exception, context = {})
      correlation_id = LoggingInfrastructure::CorrelationId.current
      error_context = extract_error_context(exception).merge(context)
      severity = determine_severity(exception)
      fingerprint = generate_fingerprint(exception)

      log_entry = {
        event: 'exception_raised',
        correlation_id:,
        error: {
          class: exception.class.name,
          message: exception.message,
          backtrace: clean_backtrace(exception.backtrace),
          fingerprint:,
          cause: extract_cause(exception),
        },
        context: error_context,
        severity:,
        alert_sent: should_alert?(exception, severity),
      }

      logger.error("Exception occurred: #{exception.message}", log_entry)

      if should_send_slack_alert?(exception, severity)
        send_slack_notification(exception, error_context.merge(
          correlation_id:,
          severity:,
          fingerprint:
        ))
      end

      track_error_metrics(exception, severity)
    rescue StandardError => e
      # Ensure error handler itself doesn't crash the application
      Rails.logger.error "Error in ErrorHandler: #{e.message}" if defined?(Rails.logger)
    end

    def log_security_event(event_type, details = {})
      return unless SECURITY_EVENTS.key?(event_type)

      log_entry = {
        event: 'security_event',
        event_type:,
        event_description: SECURITY_EVENTS[event_type],
        correlation_id: LoggingInfrastructure::CorrelationId.current,
        user_id: Thread.current[:current_user_id],
        ip_address: Thread.current[:remote_ip],
        details: sanitize_details(details),
        timestamp: Time.current.iso8601(3),
      }

      logger.warn("Security event: #{SECURITY_EVENTS[event_type]}", log_entry)

      return unless %i[unauthorized_access suspicious_activity].include?(event_type)

      send_security_slack_alert(event_type, log_entry)
    end

    def log_suspicious_activity(user_id, activity_type, details = {})
      log_entry = {
        event: 'suspicious_activity',
        activity_type:,
        user_id:,
        correlation_id: LoggingInfrastructure::CorrelationId.current,
        ip_address: Thread.current[:remote_ip],
        user_agent: Thread.current[:user_agent],
        details: sanitize_details(details),
        timestamp: Time.current.iso8601(3),
      }

      logger.warn('Suspicious activity detected', log_entry)

      return unless should_alert_suspicious_activity?(activity_type, details)

      send_suspicious_activity_slack_alert(user_id, activity_type, log_entry)
    end

    private

    def logger
      @logger ||= if defined?(Rails) && Rails.logger.is_a?(LoggingInfrastructure::StructuredLogger)
                    Rails.logger
                  else
                    LoggingInfrastructure::StructuredLogger.new
                  end
    end

    attr_writer :logger

    def extract_error_context(_exception)
      context = {
        user_id: Thread.current[:current_user_id],
        session_id: Thread.current[:session_id],
        request_id: Thread.current[:request_id],
        controller: Thread.current[:controller_name],
        action: Thread.current[:action_name],
        request_path: Thread.current[:request_path],
        request_method: Thread.current[:request_method],
        params: Thread.current[:filtered_params],
      }.compact

      # Add Rails-specific context if available
      if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
        context[:rails_root] = Rails.root.to_s
        context[:rails_env] = Rails.env
      end

      context
    end

    def determine_severity(exception)
      exception_class = exception.class.name

      SEVERITY_LEVELS.each do |level, classes|
        return level if classes.include?(exception_class)

        # Check inheritance
        classes.each do |class_name|
          klass = begin
            class_name.constantize
          rescue StandardError
            nil
          end
          return level if klass && exception.is_a?(klass)
        end
      end

      :medium # default severity
    end

    def generate_fingerprint(exception)
      # Generate a consistent fingerprint for grouping similar errors
      backtrace_line = exception.backtrace&.find { |line| line.include?(Rails.root.to_s) } if defined?(Rails)
      backtrace_line ||= exception.backtrace&.first

      Digest::MD5.hexdigest([
        exception.class.name,
        exception.message.to_s.gsub(/\d+/, 'N').gsub(/0x[0-9a-f]+/i, '0xHEX'),
        backtrace_line,
      ].join('|'))
    end

    def clean_backtrace(backtrace)
      return [] unless backtrace

      if defined?(Rails) && Rails.respond_to?(:backtrace_cleaner)
        Rails.backtrace_cleaner.clean(backtrace).first(10)
      else
        backtrace.first(10)
      end
    end

    def extract_cause(exception)
      return nil unless exception.cause

      {
        class: exception.cause.class.name,
        message: exception.cause.message,
        backtrace: clean_backtrace(exception.cause.backtrace).first(3),
      }
    end

    def should_alert?(_exception, severity)
      return false if Rails.env.development? || Rails.env.test?

      %i[critical high].include?(severity)
    end

    def should_send_slack_alert?(exception, severity)
      return false unless should_alert?(exception, severity)
      return false unless slack_configured?

      # Rate limiting - prevent spam
      rate_limit_key = "error_alert:#{generate_fingerprint(exception)}"
      !recently_alerted?(rate_limit_key)
    end

    def slack_configured?
      Rails.application.credentials.dig(:slack, :webhook_url).present?
    rescue StandardError
      false
    end

    def recently_alerted?(key)
      # Simple in-memory rate limiting
      @alert_timestamps ||= {}
      last_alert = @alert_timestamps[key]

      if last_alert && (Time.current - last_alert) < 300 # 5 minutes
        true
      else
        @alert_timestamps[key] = Time.current
        # Clean old entries
        @alert_timestamps.delete_if { |_k, v| (Time.current - v) > 3600 }
        false
      end
    end

    def send_slack_notification(exception, context)
      return unless slack_configured?

      notifier = ::Notifier::Slack.new
      message = format_slack_message(exception, context)
      notifier.send(message)
    rescue StandardError => e
      logger.error('Failed to send Slack notification', error: e.message)
    end

    def format_slack_message(exception, context)
      color = severity_color(context[:severity])

      {
        text: '🚨 *Application Error Detected*',
        attachments: [
          {
            color:,
            title: exception.class.name,
            text: exception.message.truncate(200),
            fields: [
              { title: 'Severity', value: context[:severity].to_s.capitalize, short: true },
              { title: 'Environment', value: Rails.env, short: true },
              { title: 'Correlation ID', value: context[:correlation_id] || 'N/A', short: true },
              { title: 'User ID', value: context[:user_id] || 'N/A', short: true },
              { title: 'Path', value: "#{context[:request_method]} #{context[:request_path]}", short: false },
              { title: 'Controller', value: "#{context[:controller]}##{context[:action]}", short: false },
              { title: 'Fingerprint', value: context[:fingerprint], short: false },
            ],
            footer: Socket.gethostname,
            ts: Time.current.to_i,
          },
        ],
      }
    end

    def send_security_slack_alert(event_type, log_entry)
      return unless slack_configured?

      notifier = ::Notifier::Slack.new
      message = {
        text: '🔐 *Security Alert*',
        attachments: [
          {
            color: 'warning',
            title: SECURITY_EVENTS[event_type],
            fields: [
              { title: 'Event Type', value: event_type.to_s, short: true },
              { title: 'User ID', value: log_entry[:user_id] || 'Anonymous', short: true },
              { title: 'IP Address', value: log_entry[:ip_address] || 'Unknown', short: true },
              { title: 'Correlation ID', value: log_entry[:correlation_id] || 'N/A', short: true },
              { title: 'Details', value: log_entry[:details].to_json.truncate(500), short: false },
            ],
            footer: Socket.gethostname,
            ts: Time.current.to_i,
          },
        ],
      }
      notifier.send(message)
    rescue StandardError => e
      logger.error('Failed to send security Slack alert', error: e.message)
    end

    def send_suspicious_activity_slack_alert(user_id, activity_type, log_entry)
      return unless slack_configured?

      notifier = ::Notifier::Slack.new
      message = {
        text: '⚠️ *Suspicious Activity Detected*',
        attachments: [
          {
            color: 'warning',
            title: 'Suspicious Activity',
            fields: [
              { title: 'Activity Type', value: activity_type.to_s, short: true },
              { title: 'User ID', value: user_id.to_s, short: true },
              { title: 'IP Address', value: log_entry[:ip_address] || 'Unknown', short: true },
              { title: 'User Agent', value: log_entry[:user_agent] || 'Unknown', short: false },
              { title: 'Details', value: log_entry[:details].to_json.truncate(500), short: false },
            ],
            footer: Socket.gethostname,
            ts: Time.current.to_i,
          },
        ],
      }
      notifier.send(message)
    rescue StandardError => e
      logger.error('Failed to send suspicious activity Slack alert', error: e.message)
    end

    def severity_color(severity)
      case severity
      when :critical
        'danger'
      when :high
        '#ff9900'
      when :medium
        'warning'
      else
        '#cccccc'
      end
    end

    def should_alert_suspicious_activity?(activity_type, _details)
      # Define criteria for alerting on suspicious activities
      high_risk_activities = %i[
        multiple_failed_logins
        privilege_escalation_attempt
        data_export_attempt
        api_abuse
      ]

      high_risk_activities.include?(activity_type)
    end

    def sanitize_details(details)
      return {} unless details.is_a?(Hash)

      details.transform_values do |value|
        if value.is_a?(String) && value.match?(/password|token|secret|key/i)
          '[FILTERED]'
        else
          value
        end
      end
    end

    def track_error_metrics(exception, severity)
      # Track error metrics for monitoring
      Thread.current[:error_count] ||= 0
      Thread.current[:error_count] += 1

      Thread.current[:errors_by_severity] ||= {}
      Thread.current[:errors_by_severity][severity] ||= 0
      Thread.current[:errors_by_severity][severity] += 1

      Thread.current[:errors_by_class] ||= {}
      Thread.current[:errors_by_class][exception.class.name] ||= 0
      Thread.current[:errors_by_class][exception.class.name] += 1
    end

  end

end
