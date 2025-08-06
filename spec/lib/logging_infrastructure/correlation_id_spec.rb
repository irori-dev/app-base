# frozen_string_literal: true

require 'rails_helper'

RSpec.describe LoggingInfrastructure::CorrelationId do
  describe '.current' do
    it 'returns nil when no ID is set' do
      described_class.reset
      expect(described_class.current).to be_nil
    end

    it 'returns the set correlation ID' do
      described_class.set('test_id')
      expect(described_class.current).to eq('test_id')
    ensure
      described_class.reset
    end
  end

  describe '.set' do
    it 'sets the correlation ID' do
      described_class.set('new_id')
      expect(described_class.current).to eq('new_id')
    ensure
      described_class.reset
    end
  end

  describe '.generate' do
    it 'generates a correlation ID with prefix' do
      id = described_class.generate
      expect(id).to match(/^req_[a-f0-9]{32}$/)
    end

    it 'generates unique IDs' do
      ids = Array.new(10) { described_class.generate }
      expect(ids.uniq.size).to eq(10)
    end
  end

  describe '.with_id' do
    it 'temporarily sets correlation ID within block' do
      described_class.set('original_id')

      described_class.with_id('temp_id') do
        expect(described_class.current).to eq('temp_id')
      end

      expect(described_class.current).to eq('original_id')
    ensure
      described_class.reset
    end

    it 'restores original ID even if block raises' do
      described_class.set('original_id')

      expect do
        described_class.with_id('temp_id') do
          expect(described_class.current).to eq('temp_id')
          raise 'Test error'
        end
      end.to raise_error('Test error')

      expect(described_class.current).to eq('original_id')
    ensure
      described_class.reset
    end
  end

  describe '.reset' do
    it 'clears the correlation ID' do
      described_class.set('test_id')
      described_class.reset
      expect(described_class.current).to be_nil
    end
  end

  describe '.ensure_present' do
    it 'returns existing ID if present' do
      described_class.set('existing_id')
      expect(described_class.ensure_present).to eq('existing_id')
    ensure
      described_class.reset
    end

    it 'generates and sets new ID if not present' do
      described_class.reset
      id = described_class.ensure_present
      expect(id).to match(/^req_/)
      expect(described_class.current).to eq(id)
    ensure
      described_class.reset
    end
  end

  describe '.extract_from_headers' do
    it 'extracts from X-Correlation-ID header' do
      headers = { 'X-Correlation-ID' => 'corr_123' }
      expect(described_class.extract_from_headers(headers)).to eq('corr_123')
    end

    it 'extracts from HTTP_X_CORRELATION_ID header' do
      headers = { 'HTTP_X_CORRELATION_ID' => 'corr_456' }
      expect(described_class.extract_from_headers(headers)).to eq('corr_456')
    end

    it 'extracts from X-Request-ID header as fallback' do
      headers = { 'X-Request-ID' => 'req_789' }
      expect(described_class.extract_from_headers(headers)).to eq('req_789')
    end

    it 'prioritizes X-Correlation-ID over other headers' do
      headers = {
        'X-Correlation-ID' => 'primary',
        'X-Request-ID' => 'fallback',
      }
      expect(described_class.extract_from_headers(headers)).to eq('primary')
    end

    it 'returns nil when no relevant headers present' do
      headers = { 'Content-Type' => 'application/json' }
      expect(described_class.extract_from_headers(headers)).to be_nil
    end
  end

  describe '.add_to_headers' do
    it 'adds correlation ID to headers' do
      headers = {}
      described_class.add_to_headers(headers, 'test_id')
      expect(headers['X-Correlation-ID']).to eq('test_id')
    end

    it 'uses current ID if no ID provided' do
      described_class.set('current_id')
      headers = {}
      described_class.add_to_headers(headers)
      expect(headers['X-Correlation-ID']).to eq('current_id')
    ensure
      described_class.reset
    end

    it 'generates ID if none exists' do
      described_class.reset
      headers = {}
      described_class.add_to_headers(headers)
      expect(headers['X-Correlation-ID']).to match(/^req_/)
    ensure
      described_class.reset
    end
  end

  describe 'thread safety' do
    it 'maintains separate IDs per thread' do
      ids = []
      threads = []

      3.times do |i|
        threads << Thread.new do
          described_class.set("thread_#{i}")
          sleep 0.01 # Ensure threads run concurrently
          ids << described_class.current
        end
      end

      threads.each(&:join)

      expect(ids).to match_array(%w[thread_0 thread_1 thread_2])
    ensure
      described_class.reset
    end
  end
end
