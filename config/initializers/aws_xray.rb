# frozen_string_literal: true

# AWS X-Ray integration for distributed tracing
# Only enabled in production/staging environments

if Rails.env.production? || Rails.env.staging?
  aws_config = Rails.application.config_for(:aws_logging)
  xray_config = aws_config.dig('xray') || {}

  if xray_config['enabled'] == true || xray_config['enabled'] == 'true'
    begin
      require 'aws-xray-sdk'

      XRay.configure do |config|
        config.name = Rails.application.class.module_parent_name.underscore
        config.daemon_address = xray_config['daemon_address'] || '127.0.0.1:2000'
        config.context_missing = (xray_config['context_missing'] || 'log_error').to_sym
        config.sampling_rate = xray_config['sampling_rate'] || 0.1

        # Configure segments to capture
        config.segment_rules = [
          {
            description: 'Rails Application',
            service_name: Rails.application.class.module_parent_name.underscore,
            http: {
              method: '*',
              host: '*',
              url_path: '*'
            },
            fixed_target: 0,
            rate: xray_config['sampling_rate'] || 0.1
          }
        ]

        # Add metadata
        config.metadata = {
          rails_version: Rails.version,
          ruby_version: RUBY_VERSION,
          environment: Rails.env
        }
      end

      # Insert X-Ray middleware at the beginning of the middleware stack
      Rails.application.config.middleware.insert 0, XRay::Rack::Middleware

      # Patch AWS SDK calls if AWS SDK is available
      if defined?(Aws)
        XRay.recorder.configure do |config|
          config.patch_aws_sdk_client = true
        end
      end

      # Patch HTTP calls
      require 'aws-xray-sdk/facets/net_http'
      XRay.recorder.configure do |config|
        config.patch_net_http = true
      end

      # Integrate with correlation ID
      Rails.application.config.after_initialize do
        if defined?(LoggingInfrastructure::CorrelationId)
          # Add correlation ID to X-Ray segments
          XRay.recorder.configure do |config|
            config.context_processor = lambda do |segment|
              correlation_id = LoggingInfrastructure::CorrelationId.current
              segment.metadata['correlation_id'] = correlation_id if correlation_id
            end
          end
        end
      end

      Rails.logger.info "AWS X-Ray tracing enabled with sampling rate: #{xray_config['sampling_rate']}"
    rescue LoadError => e
      Rails.logger.warn "AWS X-Ray SDK not available: #{e.message}. Add 'aws-xray-sdk' to your Gemfile to enable tracing."
    rescue StandardError => e
      Rails.logger.error "Failed to configure AWS X-Ray: #{e.message}"
    end
  else
    Rails.logger.info 'AWS X-Ray tracing disabled'
  end
end