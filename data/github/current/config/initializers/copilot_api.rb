# typed: true
# frozen_string_literal: true

require "faraday"

module CopilotAPI

  SERVICE_NAME = "copilot-api".freeze

  VERSION_2023_07_07 = "2023-07-07"
  VERSION_2025_05_01 = "2025-05-01"
  VERSION_DEFAULT = VERSION_2023_07_07

  CHAT_BASE_PATH = "/github/chat".freeze
  DOCSETS_BASE_PATH = "/github/knowledge_bases".freeze

  INTEGRATION_SUFFIX = if Rails.env == "development"
    "-dev"
  else
    ""
  end

  COPILOT_4_PRS_INTEGRATION_ID = "copilot-4-prs#{INTEGRATION_SUFFIX}".freeze
  COPILOT_WORKSPACE_EDITOR_INTEGRATION_ID = "copilot-code-reviser-agent#{INTEGRATION_SUFFIX}".freeze
  COPILOT_CHAT_INTEGRATION_ID = "copilot-chat#{INTEGRATION_SUFFIX}".freeze
  COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID = "copilot-knowledge-base#{INTEGRATION_SUFFIX}".freeze
  COPILOT_PR_REVIEWS_INTEGRATION_ID = "copilot-pr-reviews#{INTEGRATION_SUFFIX}".freeze
  COPILOT_EMBEDDED_EXPERIENCE_INTEGRATION_ID = "copilot-embedded-experience#{INTEGRATION_SUFFIX}".freeze
  COPILOT_SWE_AGENT = "copilot-developer#{INTEGRATION_SUFFIX}".freeze

  GITHUB_USER_HEADER = "X-GitHub-User".freeze
  TOKEN_HEADER = "X-Copilot-Api-Token"
  GITHUB_REQUEST_ID_HEADER = "X-GitHub-Request-Id"
  DEFAULT_RETRY_WAIT = 1.0

  MAX_CONCURRENCY = if Rails.env == "development"
    2
  else
    10
  end

  MAX_RETRIES = 3

  # DO NOT ADD VALUES TO THIS LIST WITHOUT APPROVAL FROM
  # @github/copilot-platform-team
  # EACH FEATURE MUST HAVE ITS OWN IDENTIFIER
  FEATURE_IDENTIFIERS = [
    COPILOT_4_PRS_INTEGRATION_ID,
    COPILOT_WORKSPACE_EDITOR_INTEGRATION_ID,
    COPILOT_CHAT_INTEGRATION_ID,
    COPILOT_KNOWLEDGE_BASE_INTEGRATION_ID,
    COPILOT_PR_REVIEWS_INTEGRATION_ID,
    COPILOT_EMBEDDED_EXPERIENCE_INTEGRATION_ID,
    COPILOT_SWE_AGENT,
  ].freeze

  STREAMING_MESSAGE_DELIMITER = "\n\n"
  STREAMING_MESSAGE_REGEXP = /^data:\s+/
  STREAMING_MESSAGE_END = "[DONE]"

  class Disabled < StandardError
    def initialize(message = nil)
      super(message || "copilot-platform-api is not enabled")
    end
  end

  class UnknownFeature < StandardError
    def initialize(message = nil)
      super(message || "copilot-platform-api unknown feature identifier")
    end
  end

  class Error < StandardError; end
  class EntityTooLargeError < Error; end
  class NetworkError < Error; end
  class RequestError < Error; end
  class RAIError < Error; end
  class RateLimitError < Error; end
  class NotFoundError < Error; end
  class UnauthorizedError < Error; end
  class QuotaExceededError < Error; end

  def self.enabled?
    !GitHub.enterprise?
  end

  sig do
    params(
      token: T.nilable(T.any(Copilot::DecryptedToken, Copilot::EncryptedToken)),
      integration_id: String,
      user_id: T.nilable(Integer),
      real_ip: T.nilable(String),
      method: Symbol,
      path: String,
      data: T.nilable(T.any(T::Hash[Symbol, T.untyped], String)),
      query: T.nilable(T::Hash[Symbol, T.untyped]),
      async: T::Boolean,
      retries: Integer,
      experiment_headers: T::Hash[String, String],
      interaction_id: T.nilable(String),
      interaction_type: T.nilable(String),
      initiator: T.nilable(String),
      retry_wait: T.nilable(Float),
      retry_401s: T.nilable(T::Boolean),
      copilot_api_version: T.nilable(String),
      snippy_token: T.nilable(String),
      request_id: T.nilable(String),
      request_timeout_s: T.nilable(Float),
      num_threads: T.nilable(Integer)
    ).returns(T.any(
      ConcurrentFaraday::FutureResponse[ActiveSupport::HashWithIndifferentAccess],
      ActiveSupport::HashWithIndifferentAccess
    ))
  end
  def self.make_request(
    token:,
    integration_id:,
    user_id:,
    real_ip:,
    method:,
    path:,
    data: {},
    query: {},
    async: false,
    retries: MAX_RETRIES,
    experiment_headers: {},
    interaction_id: nil,
    interaction_type: nil,
    initiator: nil,
    retry_wait: DEFAULT_RETRY_WAIT,
    retry_401s: false,
    copilot_api_version: VERSION_DEFAULT,
    snippy_token: nil,
    request_id: nil,
    request_timeout_s: nil,
    num_threads: nil
  )
    raise UnknownFeature unless FEATURE_IDENTIFIERS.include?(integration_id)
    # in a GET request, data are the query params.
    # in a POST request, data is the body.
    # to ensure that apiVersion is in the path, set it explicitly
    # if we are retrying this has already been done and we do not need to recalculate

    # if the path already includes the apiversion, we do not need to append it again
    unless path.include?("?apiVersion=")
      path = append_api_version(path, query, copilot_api_version)
      if [:post, :patch].include?(method.to_sym)
        data = data.to_json
      end
    end

    sender = async ? async_connection(integration_id: integration_id, num_threads: num_threads) : connection(integration_id: integration_id)
    raw_res = sender.send(method, path, data, experiment_headers) do |req|
      req.headers[:authorization] = make_auth_header(token)
      req.headers[:copilot_integration_id] = integration_id
      req.headers[GITHUB_USER_HEADER] = user_id
      req.headers[:x_real_ip] = real_ip unless real_ip.nil?
      # headers for billing purposes
      req.headers[:x_interaction_id] = interaction_id unless interaction_id.nil?
      req.headers[:x_interaction_type] = interaction_type unless interaction_type.nil?
      req.headers[:x_initiator] = initiator unless initiator.nil?
      req.headers[GITHUB_REQUEST_ID_HEADER] = request_id unless request_id.nil?
      req.headers[:x_snippy_token] = snippy_token unless snippy_token.nil?
      if request_timeout_s
        req.options.timeout = request_timeout_s
      end
    end

    if raw_res.is_a?(ConcurrentFaraday::FutureResponse)
      raw_res.then do |res|
        begin
          retry_header = res.headers["X-Ratelimit-User-Retry-After"]&.to_f
          wait = retry_header.is_a?(Float) && retry_header > 0 ? retry_header : retry_wait

          should_retry = self.handle_request_error(res, token, retries, retry_401s)
          if should_retry
            sleep(T.must(wait))
            make_request(
              token:,
              integration_id:,
              user_id:,
              real_ip:,
              method:,
              path:,
              data:,
              query:,
              async:,
              retries: retries - 1,
              interaction_id:,
              interaction_type:,
              initiator:,
              retry_wait:,
              retry_401s:,
              copilot_api_version:,
              snippy_token:,
              request_id:,
              request_timeout_s:,
            )
          else
            res.body.blank? ? ActiveSupport::HashWithIndifferentAccess.new : JSON.parse(res.body).with_indifferent_access
          end
        rescue CopilotAPI::RateLimitError => e
          raise RateLimitError.new(res.body) if retries <= 0
          sleep(T.must(wait))
          make_request(
            token:,
            integration_id:,
            user_id:,
            real_ip:,
            method:,
            path:,
            data:,
            query:,
            async:,
            retries: retries - 1,
            interaction_id:,
            interaction_type:,
            initiator:,
            retry_wait:,
            retry_401s:,
            copilot_api_version:,
            snippy_token:,
            request_id:,
            request_timeout_s:,
          )
        end
      end
    else # `raw_res` is Faraday::Response
      should_retry = self.handle_request_error(raw_res, token, retries, retry_401s)
      if should_retry
        sleep(T.must(retry_wait))
        make_request(
          token:,
          integration_id:,
          user_id:,
          real_ip:,
          method:,
          path:,
          data:,
          query:,
          async:,
          retries: retries - 1,
          interaction_id:,
          interaction_type:,
          initiator:,
          retry_wait:,
          retry_401s:,
          copilot_api_version:,
          snippy_token:,
          request_id:,
          request_timeout_s:,
        )
      else
        return ActiveSupport::HashWithIndifferentAccess.new if raw_res.body.blank?
        if raw_res.headers["Content-Type"] == "text/event-stream"
          handle_event_stream(raw_res)
        else
          JSON.parse(raw_res.body).with_indifferent_access
        end
      end
    end
  rescue Faraday::Error => e
    raise NetworkError.new(e.message)
  end

  sig { params(res: Faraday::Response).returns(ActiveSupport::HashWithIndifferentAccess) }
  def self.handle_event_stream(res)
    results = res.body.split(STREAMING_MESSAGE_DELIMITER)
      .map { |event| event.sub(STREAMING_MESSAGE_REGEXP, "") }
      .reject { |event| event.starts_with?(STREAMING_MESSAGE_END) }
      .map { |chunk| JSON.parse(chunk).with_indifferent_access }
    if results.size == 1 && results.first.is_a?(Hash)
      results.first.with_indifferent_access
    else
      { results: results }.with_indifferent_access
    end
  end
  private_class_method :handle_event_stream

  def self.handle_request_error(res, token, retries, retry_401s)
    return if res.status == 200 || res.success?

    case res.status
    when 401
      if retry_401s && retries > 0 && token.present?
        return true
      end
      raise UnauthorizedError.new(res.body)
    when 402
      raise QuotaExceededError.new(res.body)
    when 403
      raise RAIError.new("The response was filtered due to the content of the request. Please contact our support team.") if res.body == "content_filtered in response"
      raise RequestError.new(res.body)
    when 404
      raise NotFoundError.new(res.body)
    when 413
      raise EntityTooLargeError.new(res.body)
    when 429
      raise RateLimitError.new(res.body)
    when 400..499
      raise RequestError.new(res.body)
    when 500
      raise NetworkError.new("server encountered an internal error (HTTP 500) with response: #{res.body}")
    else
      raise NetworkError.new("something unexpected happened. HTTP Status: #{res.status}")
    end
  end
  private_class_method :handle_request_error

  def self.connection(integration_id:)
    if integration_id == COPILOT_SWE_AGENT
      @connection_copilot_developer ||= connection_inner(hmac_secret: GitHub::Config::CopilotAPI.copilot_developer_hmac_secret)
    else
      @connection ||= connection_inner(hmac_secret: GitHub::Config::CopilotAPI.hmac_secret)
    end
  end

  def self.async_connection(integration_id:, num_threads: 1)
    if integration_id == COPILOT_SWE_AGENT
      @async_connection_copilot_developer ||= async_connection_inner(hmac_secret: GitHub::Config::CopilotAPI.copilot_developer_hmac_secret, num_threads: num_threads)
    else
      @async_connection ||= async_connection_inner(hmac_secret: GitHub::Config::CopilotAPI.hmac_secret, num_threads: num_threads)
    end
  end

  def self.connection_inner(hmac_secret:)
    raise CopilotAPI::Disabled if !enabled?
    ::GitHub::FaradayClient::Internal.new(
      GitHub.copilot_api_internal_url,
      ssl: nil
    ) do |conn|
      conn.options[:open_timeout] = 0.250
      conn.options[:params_encoder] = Faraday::FlatParamsEncoder
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"

      conn.request :retry,
        max:                 3,
        interval:            0.050,
        interval_randomness: 0.5,
        backoff_factor:      1.2,
        exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
        retry_block: proc { GitHub.dogstats.increment("rest.#{SERVICE_NAME}.retries") }

      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
      conn.use ::GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_secret
      conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2

      conn.adapter :typhoeus
      yield conn if block_given?
    end
  end

  def self.async_connection_inner(hmac_secret:, num_threads: 1)
    raise CopilotAPI::Disabled if !enabled?
    ::ConcurrentFaraday.new(
      GitHub.copilot_api_internal_url,
      ssl: nil,
      num_threads: num_threads
    ) do |conn|
      conn.options[:open_timeout] = 0.250
      conn.options[:params_encoder] = Faraday::FlatParamsEncoder
      conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
      conn.headers[:content_type] = "application/json"

      conn.request :retry,
        max:                 3,
        interval:            0.050,
        interval_randomness: 0.5,
        backoff_factor:      1.2,
        exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
        retry_block: proc { GitHub.dogstats.increment("rest.#{SERVICE_NAME}.retries") }

      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
      conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
      conn.use ::GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_secret
      conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
      conn.adapter :concurrent_adapter, persistent: true
      yield conn if block_given?
    end
  end

  def self.append_api_version(path, query, copilot_api_version)
    url = Addressable::URI.parse(path)
    query[:apiVersion] = copilot_api_version
    url.query_values = query
    url.to_str
  end
  private_class_method :append_api_version

  def self.make_auth_header(token)
    return nil unless token.present?
    token.authorization_header_value
  end
  private_class_method :make_auth_header
end
