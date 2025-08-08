# frozen_string_literal: true

module LoggingHelpers

  def with_structured_logging
    original_logger = Rails.logger
    output = StringIO.new
    test_logger = LoggingInfrastructure::StructuredLogger.new(output:)
    Rails.logger = test_logger

    yield test_logger, output
  ensure
    Rails.logger = original_logger
  end

  def expect_log_entry(output, level:, message:, **metadata)
    output.rewind
    logs = output.read.split("\n").map { |line| JSON.parse(line) }

    matching_log = logs.find do |log|
      log['level'] == level.to_s &&
        log['message'] == message &&
        metadata.all? { |key, value| log.dig(*key.to_s.split('.')) == value }
    end

    expect(matching_log).not_to be_nil,
      "Expected to find log entry with level: #{level}, message: #{message}, metadata: #{metadata}"
  end

  def with_correlation_id(id = nil)
    old_id = LoggingInfrastructure::CorrelationId.current
    correlation_id = id || LoggingInfrastructure::CorrelationId.generate
    LoggingInfrastructure::CorrelationId.set(correlation_id)

    yield correlation_id
  ensure
    LoggingInfrastructure::CorrelationId.set(old_id)
  end

  def capture_logs
    output = StringIO.new
    logger = LoggingInfrastructure::StructuredLogger.new(output:)

    yield logger

    output.rewind
    output.read.split("\n").map { |line| JSON.parse(line) }
  end

  def stub_slack_notifications
    allow_any_instance_of(Notifier::Slack).to receive(:send).and_return(true)
  end

end

RSpec.configure do |config|
  config.include LoggingHelpers
end
