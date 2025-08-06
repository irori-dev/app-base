# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggingInfrastructure::RequestMiddleware do
  let(:app) { ->(_env) { [200, { 'Content-Type' => 'text/plain' }, ['OK']] } }
  let(:output) { StringIO.new }
  let(:logger) { LoggingInfrastructure::StructuredLogger.new(output:) }
  let(:middleware) { described_class.new(app, logger:) }

  def make_request(path = '/', method = 'GET', headers = {})
    env = Rack::MockRequest.env_for(path, method:, 'HTTP_HOST' => 'example.com').merge(headers)
    middleware.call(env)
  end

  describe '#call' do
    it 'sets correlation ID for request' do
      status, headers, _body = make_request

      expect(status).to eq(200)
      expect(headers['X-Correlation-ID']).to match(/^req_/)
    end

    it 'uses existing correlation ID from headers' do
      _, headers, _body = make_request('/', 'GET', 'HTTP_X_CORRELATION_ID' => 'existing_id')

      expect(headers['X-Correlation-ID']).to eq('existing_id')
    end

    it 'logs request start and end' do
      make_request('/api/users', 'POST')

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      start_log = logs.find { |l| l['event'] == 'request_started' }
      end_log = logs.find { |l| l['event'] == 'request_completed' }

      expect(start_log).not_to be_nil
      expect(start_log['request']['path']).to eq('/api/users')
      expect(start_log['request']['method']).to eq('POST')

      expect(end_log).not_to be_nil
      expect(end_log['response']['status']).to eq(200)
      expect(end_log['response']['duration_ms']).to be_a(Float)
    end

    it 'skips logging for excluded paths' do
      make_request('/health')
      make_request('/assets/app.js')

      output.rewind
      logs = output.read

      expect(logs).to be_empty
    end

    it 'logs request errors' do
      error_app = ->(_env) { raise StandardError, 'Test error' }
      error_middleware = described_class.new(error_app, logger:)

      expect do
        env = Rack::MockRequest.env_for('/')
        error_middleware.call(env)
      end.to raise_error(StandardError, 'Test error')

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      error_log = logs.find { |l| l['event'] == 'request_failed' }
      expect(error_log).not_to be_nil
      expect(error_log['error']['class']).to eq('StandardError')
      expect(error_log['error']['message']).to eq('Test error')
    end

    it 'clears request context after completion' do
      make_request

      expect(Thread.current[:request_id]).to be_nil
      expect(Thread.current[:session_id]).to be_nil
      expect(Thread.current[:current_user_id]).to be_nil
      expect(LoggingInfrastructure::CorrelationId.current).to be_nil
    end
  end

  describe 'request metadata extraction' do
    it 'extracts request information' do
      make_request('/api/users?page=1', 'POST', {
        'HTTP_USER_AGENT' => 'Mozilla/5.0',
        'HTTP_REFERER' => 'https://example.com',
        'CONTENT_TYPE' => 'application/json',
      })

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      log = logs.find { |l| l['event'] == 'request_completed' }
      request_data = log['request']

      expect(request_data['method']).to eq('POST')
      expect(request_data['path']).to eq('/api/users')
      expect(request_data['user_agent']).to eq('Mozilla/5.0')
      expect(request_data['referer']).to eq('https://example.com')
    end
  end

  describe 'performance metrics' do
    it 'tracks request duration' do
      make_request

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      log = logs.find { |l| l['event'] == 'request_completed' }
      expect(log['response']['duration_ms']).to be > 0
      expect(log['response']['duration_ms']).to be < 1000
    end

    it 'calculates response size' do
      app_with_body = ->(_env) { [200, {}, ['Hello World']] }
      middleware_with_body = described_class.new(app_with_body, logger:)

      env = Rack::MockRequest.env_for('/')
      middleware_with_body.call(env)

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      log = logs.find { |l| l['event'] == 'request_completed' }
      expect(log['response']['size_bytes']).to eq(11) # "Hello World".bytesize
    end
  end

  describe 'user context extraction' do
    it 'extracts user ID from session' do
      env = Rack::MockRequest.env_for('/')
      env['rack.session'] = { user_id: 123 }

      middleware.call(env)

      output.rewind
      logs = output.read.split("\n").map { |line| JSON.parse(line) }

      # During the request, user_id should be set
      expect(logs.any? { |l| l['user_id'] == 123 }).to be_truthy
    end
  end
end
