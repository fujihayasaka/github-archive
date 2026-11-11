# typed: true
# frozen_string_literal: true

require "monolith-twirp-copilot-mission-control-tasks"

class GitHub::CopilotMissionControl::Client::Tasks
  include GitHub::Memoizer

  # Represents an error when calling to the Tasks API
  class Error < StandardError; end
  class UnauthorizedError < Error; end
  class NetworkError < Error; end
  class ApiError < Error; end

  SERVICE_NAME = "copilot-mission-control-tasks-service"
  FAILBOT_APP_NAME = "github"

  READ_TIMEOUT = 9.0 # seconds

  ERRORS_TO_RESCUE = T.let([
    Faraday::SSLError,
    Faraday::Error,
    Faraday::ConnectionFailed,
  ].freeze, T::Array[T.class_of(Faraday::Error)])

  def self.connection
    @connection ||= new_conn(GitHub.copilot_mission_control_url)
  end

  def connection
    self.class.connection
  end

  def self.send_message_to_failbot(msg)
    error = Error.new(msg)
    error.set_backtrace(caller)
    Failbot.report(error, { app: FAILBOT_APP_NAME })
  end

  sig { returns(CopilotMissionControl::TasksAPI::V1::TasksAPIClient) }
  memoize def client
    CopilotMissionControl::TasksAPI::V1::TasksAPIClient.new(connection)
  end

  def with_error_reporting
    rpc = T.must(T.must(caller_locations(1, 1)).first).base_label
    tags = ["rpc:#{rpc}"]

    response = yield
    if response.nil?
      tags << "error:empty_response"
      GitHub.dogstats.increment("copilot_mission_control_tasks.service_error", tags: tags)
      message = "Nil response from #{SERVICE_NAME}"
      self.class.send_message_to_failbot(message)
      raise ApiError, message
    elsif response.error && response.error.code != :not_found
      message = "Error response from #{SERVICE_NAME}: #{response.error}"
      self.class.report_failure(tags, response.error, message)
      raise ApiError, message
    end
    response
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
    params(
      options: CopilotMissionControl::TasksAPI::V1::CreateTaskRequest,
      remote_ip: T.nilable(String)
    ).returns(Twirp::ClientResp[CopilotMissionControl::TasksAPI::V1::CreateTaskResponse])
  end
  def create_task(options, remote_ip: nil)
    headers = {}
    headers["X-Real-IP"] = remote_ip if remote_ip.present?
    with_error_reporting { client.create_task(options, headers) }
  end

  def self.new_conn(service_url, timeout: READ_TIMEOUT)
    GitHub::FaradayClient::Internal.new(service_url) do |conn|
      conn.options[:open_timeout] = 0.1
      conn.options[:timeout] = timeout
      conn.headers[:user_agent] = "GitHub::CopilotMissionControl::Client::Tasks github-#{GitHub.role}/#{GitHub.current_sha}"

      conn.use GitHub::FaradayMiddleware::Retries,
        client_name: SERVICE_NAME,
        max: 3,
        exceptions: [Faraday::ConnectionFailed, Faraday::RetriableResponse],
        methods: [:post]

      conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
      conn.use GitHub::FaradayMiddleware::RequestID
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.copilot_mission_control_hmac_key
      conn.use GitHub::FaradayMiddleware::TenantContext

      conn.adapter :typhoeus
    end
  end

  def self.report_failure(tags, e, message)
    T.must(tags) << "error:#{e.class.name}"
    GitHub.dogstats.increment("copilot_mission_control_tasks.service_error", tags: tags)

    if e.is_a?(Twirp::Error)
      failbot_error = Error.new(message)
      failbot_error.set_backtrace(caller)
      Failbot.report(failbot_error, { app: FAILBOT_APP_NAME })
    else
      Failbot.report(e, { app: FAILBOT_APP_NAME })
    end
  end
end
