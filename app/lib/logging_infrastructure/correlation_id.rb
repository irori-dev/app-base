# frozen_string_literal: true

class LoggingInfrastructure::CorrelationId

  THREAD_LOCAL_KEY = :correlation_id
  ID_PREFIX = 'req_'
  ID_LENGTH = 16

  class << self

    def current
      Thread.current[THREAD_LOCAL_KEY]
    end

    def set(id)
      Thread.current[THREAD_LOCAL_KEY] = id
    end

    def generate
      "#{ID_PREFIX}#{SecureRandom.hex(ID_LENGTH)}"
    end

    def with_id(id)
      old_id = current
      set(id)
      yield
    ensure
      set(old_id)
    end

    def reset
      Thread.current[THREAD_LOCAL_KEY] = nil
    end

    def ensure_present
      current || generate.tap { |id| set(id) }
    end

    def extract_from_headers(headers)
      headers['X-Correlation-ID'] ||
        headers['HTTP_X_CORRELATION_ID'] ||
        headers['X-Request-ID'] ||
        headers['HTTP_X_REQUEST_ID']
    end

    def add_to_headers(headers, id = nil)
      correlation_id = id || ensure_present
      headers['X-Correlation-ID'] = correlation_id
      headers
    end

    def inherited_to_job(job_class)
      correlation_id = current
      return unless correlation_id

      job_class.class_eval do
        before_perform do |_job|
          CorrelationId.set(correlation_id) if correlation_id
        end

        after_perform do |_job|
          CorrelationId.reset
        end

        if respond_to?(:around_perform)
          around_perform do |_job, block|
            CorrelationId.with_id(correlation_id) do
              block.call
            end
          end
        end
      end
    end

    private

    def thread_local_key
      THREAD_LOCAL_KEY
    end

  end

end
