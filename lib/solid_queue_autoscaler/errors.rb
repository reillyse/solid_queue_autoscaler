# frozen_string_literal: true

module SolidQueueAutoscaler
  # Base error class for all autoscaler errors.
  class Error < StandardError; end

  # Raised when configuration is invalid.
  class ConfigurationError < Error; end

  # Raised when the advisory lock cannot be acquired.
  class LockError < Error; end

  # Raised when Heroku API calls fail.
  class HerokuAPIError < Error
    attr_reader :status_code, :response_body

    def initialize(message, status_code: nil, response_body: nil)
      super(message)
      @status_code = status_code
      @response_body = response_body
    end
  end

  # Raised when Kubernetes API calls fail.
  class KubernetesAPIError < Error
    attr_reader :original_error

    def initialize(message, original_error: nil)
      super(message)
      @original_error = original_error
    end
  end

  class MetricsError < Error; end

  class CooldownActiveError < Error
    attr_reader :remaining_seconds

    def initialize(remaining_seconds)
      @remaining_seconds = remaining_seconds
      super("Cooldown active, #{remaining_seconds.round}s remaining")
    end
  end
end
