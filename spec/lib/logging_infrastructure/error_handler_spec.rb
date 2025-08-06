# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggingInfrastructure::ErrorHandler do
  let(:output) { StringIO.new }
  let(:logger) { LoggingInfrastructure::StructuredLogger.new(output:) }

  before do
    described_class.send(:logger=, logger)
  end

  after do
    described_class.instance_variable_set(:@logger, nil)
    described_class.instance_variable_set(:@alert_timestamps, nil)
  end

  describe '.handle_exception' do
    let(:exception) { StandardError.new('Test error') }
    let(:context) { { controller: 'users', action: 'create' } }

    before do
      allow(exception).to receive(:backtrace).and_return([
                                                           '/app/controllers/users_controller.rb:10:in `create`',
                                                           '/app/lib/some_lib.rb:20:in `process`',
                                                         ])
    end

    it 'logs exception with context' do
      described_class.handle_exception(exception, context)

      output.rewind
      content = output.read
      expect(content).not_to be_empty

      log = JSON.parse(content)

      expect(log['event']).to eq('exception_raised')
      expect(log['error']['class']).to eq('StandardError')
      expect(log['error']['message']).to eq('Test error')
      expect(log['context']['controller']).to eq('users')
      expect(log['context']['action']).to eq('create')
    end

    it 'includes correlation ID when present' do
      LoggingInfrastructure::CorrelationId.set('test_correlation')

      described_class.handle_exception(exception, context)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['correlation_id']).to eq('test_correlation')
    ensure
      LoggingInfrastructure::CorrelationId.reset
    end

    it 'determines severity based on exception type' do
      connection_error = ActiveRecord::ConnectionNotEstablished.new('Connection failed')
      described_class.handle_exception(connection_error, context)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['severity']).to eq('critical')
    end

    it 'generates fingerprint for error grouping' do
      described_class.handle_exception(exception, context)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['error']['fingerprint']).to be_a(String)
      expect(log['error']['fingerprint'].length).to eq(32) # MD5 hash
    end

    context 'with Slack notifications' do
      before do
        allow(Rails.env).to receive(:production?).and_return(true)
        allow(Rails.env).to receive(:test?).and_return(false)
        allow(Rails.application.credentials).to receive(:dig).with(:slack, :webhook_url).and_return('https://hooks.slack.com/test')
      end

      after do
        described_class.instance_variable_set(:@alert_timestamps, nil)
      end

      it 'sends Slack notification for critical errors' do
        notifier = instance_double(Notifier::Slack)
        allow(Notifier::Slack).to receive(:new).and_return(notifier)
        expect(notifier).to receive(:send).once

        critical_error = ActiveRecord::ConnectionNotEstablished.new('DB down')
        described_class.handle_exception(critical_error, context)
      end

      it 'does not spam Slack for repeated errors' do
        notifier = instance_double(Notifier::Slack)
        allow(Notifier::Slack).to receive(:new).and_return(notifier)
        expect(notifier).to receive(:send).once # Only once despite multiple calls

        critical_error = ActiveRecord::ConnectionNotEstablished.new('DB down')
        3.times do
          described_class.handle_exception(critical_error, context)
        end
      end
    end
  end

  describe '.log_security_event' do
    it 'logs security events with appropriate level' do
      described_class.log_security_event(:authentication_failure, {
        username: 'attacker',
        ip: '192.168.1.100',
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['event']).to eq('security_event')
      expect(log['event_type']).to eq('authentication_failure')
      expect(log['event_description']).to eq('Authentication Failed')
      expect(log['details']['username']).to eq('attacker')
      expect(log['level']).to eq('warn')
    end

    it 'sends Slack alert for high-risk security events' do
      allow(Rails.application.credentials).to receive(:dig).with(:slack, :webhook_url).and_return('https://hooks.slack.com/test')

      notifier = instance_double(Notifier::Slack)
      allow(Notifier::Slack).to receive(:new).and_return(notifier)
      expect(notifier).to receive(:send).once

      described_class.log_security_event(:unauthorized_access, {
        resource: '/admin/users',
        user_id: 123,
      })
    end

    it 'filters sensitive details' do
      described_class.log_security_event(:invalid_token, {
        token: 'secret_token_123',
        user: 'test@example.com',
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['details']['token']).to eq('[FILTERED]')
      expect(log['details']['user']).to eq('test@example.com')
    end
  end

  describe '.log_suspicious_activity' do
    it 'logs suspicious user activity' do
      described_class.log_suspicious_activity(42, :multiple_failed_logins, {
        attempts: 5,
        duration: '5 minutes',
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['event']).to eq('suspicious_activity')
      expect(log['activity_type']).to eq('multiple_failed_logins')
      expect(log['user_id']).to eq(42)
      expect(log['details']['attempts']).to eq(5)
    end

    it 'includes request context when available' do
      Thread.current[:remote_ip] = '10.0.0.1'
      Thread.current[:user_agent] = 'Mozilla/5.0'

      described_class.log_suspicious_activity(42, :api_abuse, {})

      output.rewind
      log = JSON.parse(output.read)

      expect(log['ip_address']).to eq('10.0.0.1')
      expect(log['user_agent']).to eq('Mozilla/5.0')
    ensure
      Thread.current[:remote_ip] = nil
      Thread.current[:user_agent] = nil
    end

    it 'sends alerts for high-risk activities' do
      allow(Rails.application.credentials).to receive(:dig).with(:slack, :webhook_url).and_return('https://hooks.slack.com/test')

      notifier = instance_double(Notifier::Slack)
      allow(Notifier::Slack).to receive(:new).and_return(notifier)
      expect(notifier).to receive(:send).once

      described_class.log_suspicious_activity(42, :privilege_escalation_attempt, {
        target_role: 'admin',
      })
    end
  end

  describe 'error classification' do
    it 'classifies database errors as critical' do
      errors = [
        ActiveRecord::ConnectionNotEstablished.new,
        PG::ConnectionBad.new,
      ]

      errors.each do |error|
        output.truncate(0)
        output.rewind
        described_class.handle_exception(error)

        output.rewind
        content = output.read
        next if content.empty?

        log = JSON.parse(content)
        expect(log['severity']).to eq('critical')
      end
    end

    it 'classifies application errors as high severity' do
      errors = [
        NoMethodError.new,
        NameError.new,
        ActiveRecord::RecordNotFound.new,
      ]

      errors.each do |error|
        output.truncate(0)
        output.rewind
        described_class.handle_exception(error)

        output.rewind
        content = output.read
        next if content.empty?

        log = JSON.parse(content)
        expect(log['severity']).to eq('high')
      end
    end

    it 'classifies validation errors as medium severity' do
      errors = [
        ActiveRecord::RecordInvalid.new(User::Core.new),
        ActionController::ParameterMissing.new(:user),
      ]

      errors.each do |error|
        output.truncate(0)
        output.rewind
        described_class.handle_exception(error)

        output.rewind
        content = output.read
        next if content.empty?

        log = JSON.parse(content)
        expect(log['severity']).to eq('medium')
      end
    end
  end
end
