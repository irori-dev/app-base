# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggingInfrastructure::PerformanceMonitor do
  let(:output) { StringIO.new }
  let(:logger) { LoggingInfrastructure::StructuredLogger.new(level: :debug, output:) }

  before do
    described_class.send(:logger=, logger)
  end

  after do
    described_class.instance_variable_set(:@logger, nil)
  end

  describe '.track_database_query' do
    it 'logs database query execution' do
      described_class.track_database_query(
        'SELECT * FROM users WHERE id = 1',
        'User Load',
        15.5,
        { database: 'test_db' }
      )

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_type']).to eq('database_query')
      expect(log['metric_data']['duration_ms']).to eq(15.5)
      expect(log['metric_data']['name']).to eq('User Load')
      expect(log['metric_data']['table']).to eq('users')
      expect(log['metric_data']['operation']).to eq('select')
    end

    it 'marks slow queries' do
      described_class.track_database_query(
        'SELECT * FROM posts',
        'Post Load',
        150.0
      )

      output.rewind
      log = JSON.parse(output.read)

      expect(log['level']).to eq('warn')
      expect(log['metric_data']['slow']).to be true
    end

    it 'sanitizes SQL queries' do
      described_class.track_database_query(
        "SELECT * FROM users WHERE email = 'user@example.com' AND id = 12345",
        'User Load',
        10.0
      )

      output.rewind
      log = JSON.parse(output.read)

      sql = log['metric_data']['sql']
      expect(sql).not_to include('user@example.com')
      expect(sql).not_to include('12345')
      expect(sql).to include('[VALUE]')
      expect(sql).to include('[ID]')
    end

    it 'skips internal queries' do
      described_class.track_database_query('BEGIN', 'Transaction', 1.0)
      described_class.track_database_query('COMMIT', 'Transaction', 1.0)

      output.rewind
      expect(output.read).to be_empty
    end
  end

  describe '.track_cache_operation' do
    it 'logs cache operations' do
      described_class.track_cache_operation(:read, 'user:123', true, 0.5)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_type']).to eq('cache_operation')
      expect(log['metric_data']['operation']).to eq('read')
      expect(log['metric_data']['key']).to eq('user:123')
      expect(log['metric_data']['hit']).to be true
      expect(log['metric_data']['duration_ms']).to eq(0.5)
    end

    it 'filters sensitive cache keys' do
      described_class.track_cache_operation(:write, 'password_reset_token:abc', false, 1.0)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_data']['key']).to eq('[FILTERED]')
    end
  end

  describe '.track_external_api_call' do
    it 'logs API calls' do
      described_class.track_external_api_call(
        'https://api.example.com/users',
        :post,
        250.5,
        201,
        request_body: 'test',
        response_body: 'response'
      )

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_type']).to eq('external_api_call')
      expect(log['metric_data']['url']).to include('api.example.com')
      expect(log['metric_data']['method']).to eq('POST')
      expect(log['metric_data']['duration_ms']).to eq(250.5)
      expect(log['metric_data']['status']).to eq(201)
      expect(log['metric_data']['host']).to eq('api.example.com')
    end

    it 'marks slow API calls' do
      described_class.track_external_api_call(
        'https://slow-api.com/endpoint',
        :get,
        1500.0,
        200
      )

      output.rewind
      log = JSON.parse(output.read)

      expect(log['level']).to eq('warn')
      expect(log['metric_data']['slow']).to be true
    end

    it 'sanitizes URLs with sensitive parameters' do
      described_class.track_external_api_call(
        'https://api.example.com/auth?api_key=secret123&user=test',
        :get,
        100.0,
        200
      )

      output.rewind
      log = JSON.parse(output.read)

      url = log['metric_data']['url']
      expect(url).not_to include('secret123')
      expect(url).to include('[FILTERED]')
    end
  end

  describe '.track_memory_usage' do
    before do
      allow(GC).to receive(:stat).and_return({
        count: 10,
        time: 100,
        heap_allocated_slots: 50_000,
        heap_free_slots: 10_000,
      })
    end

    it 'logs memory usage metrics' do
      described_class.track_memory_usage

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_type']).to eq('memory_usage')
      expect(log['metric_data']['gc_count']).to eq(10)
      expect(log['metric_data']['heap_slots']).to eq(50_000)
    end

    it 'warns on high memory usage' do
      allow(described_class).to receive(:get_memory_usage_mb).and_return(600.0)

      described_class.track_memory_usage

      output.rewind
      log = JSON.parse(output.read)

      expect(log['level']).to eq('warn')
      expect(log['metric_data']['high_usage']).to be true
    end
  end

  describe '.track_job_performance' do
    it 'logs job completion metrics' do
      described_class.track_job_performance('TestJob', 500.0, :success)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['metric_type']).to eq('background_job')
      expect(log['metric_data']['job_class']).to eq('TestJob')
      expect(log['metric_data']['duration_ms']).to eq(500.0)
      expect(log['metric_data']['status']).to eq('success')
    end

    it 'logs job failures with error details' do
      error = StandardError.new('Job failed')
      described_class.track_job_performance('FailedJob', 100.0, :failed, error)

      output.rewind
      log = JSON.parse(output.read)

      expect(log['level']).to eq('error')
      expect(log['metric_data']['status']).to eq('failed')
      expect(log['metric_data']['error']['class']).to eq('StandardError')
      expect(log['metric_data']['error']['message']).to eq('Job failed')
    end
  end

  describe '.start_tracking and .end_tracking' do
    it 'tracks duration between start and end' do
      described_class.start_tracking
      sleep 0.01
      duration = described_class.end_tracking

      expect(duration).to be > 10.0
      expect(duration).to be < 100.0
    end
  end
end
