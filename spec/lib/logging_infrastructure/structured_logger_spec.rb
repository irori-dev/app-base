# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggingInfrastructure::StructuredLogger do
  let(:output) { StringIO.new }
  let(:logger) { described_class.new(output:) }

  describe '#initialize' do
    it 'sets default log level to info' do
      expect(logger.level).to eq(:info)
    end

    it 'accepts custom log level' do
      debug_logger = described_class.new(level: :debug, output:)
      expect(debug_logger.level).to eq(:debug)
    end
  end

  describe 'logging methods' do
    %i[debug info warn error fatal].each do |level|
      describe "##{level}" do
        it "logs message at #{level} level" do
          logger = described_class.new(level: :debug, output:)
          logger.send(level, 'Test message', foo: 'bar')

          output.rewind
          log = JSON.parse(output.read)

          expect(log['level']).to eq(level.to_s)
          expect(log['message']).to eq('Test message')
          expect(log['foo']).to eq('bar')
        end
      end
    end
  end

  describe 'log filtering by level' do
    it 'filters out messages below the configured level' do
      logger = described_class.new(level: :warn, output:)

      logger.debug('Debug message')
      logger.info('Info message')
      logger.warn('Warn message')
      logger.error('Error message')

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      expect(logs.size).to eq(2)
      expect(logs.map { |l| l['level'] }).to eq(%w[warn error])
    end
  end

  describe 'sensitive data filtering' do
    it 'filters password fields' do
      logger.info('User login', user: { email: 'test@example.com', password: 'secret123' })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['user']['email']).to eq('test@example.com')
      expect(log['user']['password']).to eq('[FILTERED]')
    end

    it 'filters API keys and tokens' do
      logger.info('API call', {
        api_key: 'sk_test_123456',
        access_token: 'bearer_token_xyz',
        public_key: 'pk_test_789',
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['api_key']).to eq('[FILTERED]')
      expect(log['access_token']).to eq('[FILTERED]')
      expect(log['public_key']).to eq('pk_test_789') # Public keys are not filtered
    end

    it 'filters nested sensitive data' do
      logger.info('Request', {
        params: {
          user: {
            name: 'John',
            password_confirmation: 'secret',
            credit_card: '4111111111111111',
          },
        },
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['params']['user']['name']).to eq('John')
      expect(log['params']['user']['password_confirmation']).to eq('[FILTERED]')
      expect(log['params']['user']['credit_card']).to eq('[FILTERED]')
    end

    it 'detects and filters sensitive-looking values' do
      logger.info('Headers', {
        authorization: 'Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9',
        'x-api-key': 'abc123def456ghi789',
        'content-type': 'application/json',
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['authorization']).to eq('[FILTERED]')
      expect(log['x-api-key']).to eq('[FILTERED]')
      expect(log['content-type']).to eq('application/json')
    end
  end

  describe 'structured logging format' do
    before do
      allow(Time).to receive(:current).and_return(Time.parse('2025-01-08 10:30:00 UTC'))
      allow(Socket).to receive(:gethostname).and_return('test-host')
      allow(Process).to receive(:pid).and_return(12_345)
    end

    it 'includes standard metadata' do
      logger.info('Test message')

      output.rewind
      log = JSON.parse(output.read)

      expect(log['timestamp']).to match(/2025-01-08T10:30:00/)
      expect(log['level']).to eq('info')
      expect(log['message']).to eq('Test message')
      expect(log['environment']).to eq('test')
      expect(log['hostname']).to eq('test-host')
      expect(log['pid']).to eq(12_345)
    end

    it 'includes correlation ID when present' do
      LoggingInfrastructure::CorrelationId.set('req_abc123')

      logger.info('Test message')

      output.rewind
      log = JSON.parse(output.read)

      expect(log['correlation_id']).to eq('req_abc123')
    ensure
      LoggingInfrastructure::CorrelationId.reset
    end

    it 'includes user context when present' do
      Thread.current[:current_user_id] = 42
      Thread.current[:session_id] = 'sess_xyz'

      logger.info('Test message')

      output.rewind
      log = JSON.parse(output.read)

      expect(log['user_id']).to eq(42)
      expect(log['session_id']).to eq('sess_xyz')
    ensure
      Thread.current[:current_user_id] = nil
      Thread.current[:session_id] = nil
    end
  end

  describe 'custom metadata' do
    it 'merges custom metadata with standard fields' do
      logger.info('Custom log', {
        request_id: 'req_123',
        action: 'create',
        duration_ms: 145.67,
      })

      output.rewind
      log = JSON.parse(output.read)

      expect(log['message']).to eq('Custom log')
      expect(log['request_id']).to eq('req_123')
      expect(log['action']).to eq('create')
      expect(log['duration_ms']).to eq(145.67)
    end
  end

  describe 'Rails logger compatibility' do
    describe 'methods without arguments' do
      it 'handles debug without arguments' do
        logger = described_class.new(level: :debug, output:)
        expect { logger.debug }.not_to raise_error

        output.rewind
        log = JSON.parse(output.read)
        expect(log['level']).to eq('debug')
        expect(log['message']).to eq('')
      end

      it 'handles info with block' do
        logger.info { 'Block message' }

        output.rewind
        log = JSON.parse(output.read)
        expect(log['message']).to eq('Block message')
      end
    end

    describe '#silence' do
      it 'temporarily changes the log level' do
        logger = described_class.new(level: :debug, output:)

        logger.debug('This should appear')

        logger.silence(:error) do
          logger.debug('This should not appear')
          logger.warn('This should not appear')
          logger.error('This should appear')
        end

        logger.debug('This should appear again')

        output.rewind
        lines = output.read.split("\n").map { |line| JSON.parse(line) }

        expect(lines.length).to eq(3)
        messages = lines.map { |l| l['message'] }
        expect(messages).to eq(['This should appear', 'This should appear', 'This should appear again'])
      end
    end

    describe '#add' do
      it 'logs messages using Logger severity constants' do
        logger.add(Logger::INFO, 'Test message')

        output.rewind
        log = JSON.parse(output.read)

        expect(log['message']).to eq('Test message')
        expect(log['level']).to eq('info')
      end
    end

    describe '#unknown' do
      it 'logs unknown messages at fatal level' do
        logger.unknown('Unknown message')

        output.rewind
        log = JSON.parse(output.read)

        expect(log['message']).to eq('Unknown message')
        expect(log['level']).to eq('fatal')
      end
    end
  end
end
