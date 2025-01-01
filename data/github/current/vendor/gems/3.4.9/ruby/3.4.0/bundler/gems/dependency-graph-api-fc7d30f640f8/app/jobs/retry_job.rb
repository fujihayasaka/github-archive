class RetryJob < ApplicationJob

  RETRYABLE_ERRORS = [
    Errno::ECONNREFUSED,
    Errno::ECONNRESET,
    Errno::ETIMEDOUT,
    Faraday::ConnectionFailed,
    Faraday::TimeoutError,
    Net::HTTPRequestTimeOut,
    Net::ReadTimeout,
    Aqueduct::Client::RequestError,
    Freno::Throttler::Error
  ].freeze

  retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    Instrument.increment("active_job.retries.retry_failed", job: job.class.to_s.underscore, error: error.class.to_s.underscore)
  end

  def perform
    raise NotImplementedError("Subclasses of #{self.klass} must implement #perform.")
  end

end
