# typed: true
# frozen_string_literal: true

require "sweagentd"

class GitHub::Sweagentd::Client::Jobs
  include GitHub::Memoizer

  # Represents an error when calling to the Jobs API
  class Error < StandardError; end
  class UnauthorizedError < Error; end
  class NetworkError < Error; end
  class ApiError < Error; end

  SERVICE_NAME = "sweagentd-jobs-service"
  FAILBOT_APP_NAME = "github"

  READ_TIMEOUT = 9.0 # seconds
  RATE_LIMIT_RETRY_DELAYS = T.let([0.5, 1.0, 2.0].freeze, T::Array[Float])
  RATE_LIMIT_MAX_RETRIES = T.let(RATE_LIMIT_RETRY_DELAYS.length, Integer)
  RATE_LIMIT_RETRY_CODES = T.let([:resource_exhausted].freeze, T::Array[Symbol])

  ERRORS_TO_RESCUE = T.let([
    Faraday::SSLError,
    Faraday::Error,
    Faraday::ConnectionFailed,
  ].freeze, T::Array[T.class_of(Faraday::Error)])

  def self.connection
    @connection ||= new_conn(GitHub.sweagentd_url)
  end

  def connection
    self.class.connection
  end

  def self.send_message_to_failbot(msg)
    error = Error.new(msg)
    error.set_backtrace(caller)
    Failbot.report(error, { app: FAILBOT_APP_NAME })
  end

  sig { returns(Sweagentd::JobsAPI::V1::JobsAPIClient) }
  memoize def client
    Sweagentd::JobsAPI::V1::JobsAPIClient.new(connection)
  end

  def with_error_reporting(rate_limit_retries: 0)
    rpc = T.must(T.must(caller_locations(1, 1)).first).base_label
    tags = ["rpc:#{rpc}"]
    attempts = 0

    loop do
      response = yield
      if response.nil?
        tags << "error:empty_response"
        GitHub.dogstats.increment("sweagentd_jobs.service_error", tags: tags)
        message = "Nil response from #{SERVICE_NAME}"
        self.class.send_message_to_failbot(message)
        # Raise an API error for the nil response
        raise ApiError, message
      elsif retryable_rate_limit_response?(response, attempts: attempts, max_retries: rate_limit_retries)
        sleep(rate_limit_retry_delay(attempts))
        attempts += 1
        next
      elsif response.error && response.error.code != :not_found
        message = "Error response from #{SERVICE_NAME}: #{response.error}"
        # Report the original error
        self.class.report_failure(tags, response.error, message)
        raise ApiError, message
      end
      return response
    end
  rescue Faraday::UnauthorizedError => e
    message = "Unauthorized error calling #{SERVICE_NAME}: #{e.message}"
    self.class.report_failure(tags, e, message)
    raise UnauthorizedError, message
  rescue *ERRORS_TO_RESCUE, RuntimeError => e
    message = "Network error calling #{SERVICE_NAME}: #{e.message}"
    self.class.report_failure(tags, e, message)
    raise NetworkError, message
  end

  sig do
    params(options: Sweagentd::JobsAPI::V1::ListJobsForPullRequestRequest)
      .returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::ListJobsForPullRequestResponse])
  end
  def list_jobs_for_pull_request(options)
    with_error_reporting { client.list_jobs_for_pull_request(options) }
  end

  sig do
    params(
      options: Sweagentd::JobsAPI::V1::CreateJobRequest,
      remote_ip: T.nilable(String)
    ).returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::CreateJobResponse])
  end
  def create_job(options, remote_ip: nil)
    headers = {}
    headers["X-Real-IP"] = remote_ip if remote_ip.present?
    with_error_reporting { client.create_job(options, headers) }
  end

  sig do
    params(options: Sweagentd::JobsAPI::V1::GetJobBySessionIDRequest)
      .returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::GetJobBySessionIDResponse])
  end
  def get_job_by_session_id(options)
    with_error_reporting { client.get_job_by_session_i_d(options) }
  end

  sig do
    params(
      options: Sweagentd::JobsAPI::V1::CreateCommandRequest,
      remote_ip: T.nilable(String)
    ).returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::CreateCommandResponse])
  end
  def create_command(options, remote_ip: nil)
    headers = {}
    headers["X-Real-IP"] = remote_ip if remote_ip.present?
    with_error_reporting { client.create_command(options, headers) }
  end

  sig do
    params(options: Sweagentd::JobsAPI::V1::ListUserMemoriesForBillingEntityRequest)
      .returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::ListUserMemoriesForBillingEntityResponse])
  end
  def list_user_memories_for_billing_entity(options)
    with_error_reporting(rate_limit_retries: RATE_LIMIT_MAX_RETRIES) do
      client.list_user_memories_for_billing_entity(options)
    end
  end

  sig do
    params(options: Sweagentd::JobsAPI::V1::DeleteUserMemoriesForBillingEntityRequest)
      .returns(Twirp::ClientResp[Sweagentd::JobsAPI::V1::DeleteUserMemoriesForBillingEntityResponse])
  end
  def delete_user_memories_for_billing_entity(options)
    with_error_reporting(rate_limit_retries: RATE_LIMIT_MAX_RETRIES) do
      client.delete_user_memories_for_billing_entity(options)
    end
  end

  def self.new_conn(service_url, timeout: READ_TIMEOUT)
    GitHub::FaradayClient::Internal.new(service_url) do |conn|
      conn.options[:open_timeout] = 0.1
      conn.options[:timeout] = timeout
      conn.headers[:user_agent] = "GitHub::Sweagentd::Client::Jobs github-#{GitHub.role}/#{GitHub.current_sha}"

      conn.use GitHub::FaradayMiddleware::Retries,
        client_name: SERVICE_NAME,
        max: 3,
        exceptions: [Faraday::ConnectionFailed, Faraday::RetriableResponse],
        methods: [:post]

      conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
      conn.use GitHub::FaradayMiddleware::RequestID
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.sweagentd_hmac_key
      conn.use GitHub::FaradayMiddleware::TenantContext

      conn.adapter :typhoeus
    end
  end

  def self.report_failure(tags, e, message)
    T.must(tags) << "error:#{e.class.name}"
    GitHub.dogstats.increment("sweagentd_jobs.service_error", tags: tags)

    # For Twirp errors, create a standard error for Failbot reporting since they don't have .message
    if e.is_a?(Twirp::Error)
      failbot_error = Error.new(message)
      failbot_error.set_backtrace(caller)
      Failbot.report(failbot_error, { app: FAILBOT_APP_NAME })
    else
      # For all other errors (including our custom ApiError, NetworkError, etc.), report directly
      Failbot.report(e, { app: FAILBOT_APP_NAME })
    end
  end

  private

  def retryable_rate_limit_response?(response, attempts:, max_retries:)
    return false unless attempts < max_retries

    error = response.error
    return false unless error

    RATE_LIMIT_RETRY_CODES.include?(error.code.to_s.to_sym)
  end

  def rate_limit_retry_delay(attempts)
    RATE_LIMIT_RETRY_DELAYS.fetch(attempts)
  end
end
