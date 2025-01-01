# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module AlertPrioritization
    class CopilotApiClient
      include GitHub::Memoizer

      CAPI_VERSION = "2023-07-07"
      MAX_RETRIES = 3

      sig { returns(::User) }; attr_reader :user
      sig { returns(String) }; attr_reader :integration_id
      sig { returns(T.nilable(T.any(Copilot::DecryptedToken, ::Copilot::EncryptedToken))) }; attr_reader :token
      sig { returns(String) }; attr_reader :hmac_secret

      sig do
        params(
          user: ::User,
          integration_id: String,
          token: T.nilable(T.any(Copilot::DecryptedToken, ::Copilot::EncryptedToken)), # For authn with a Personal Access Token. See https://gh.io/copilot-api-auth.
          hmac_secret: String # For authn with an HMAC secret. See https://gh.io/copilot-api-auth. DEFAULT: `GitHub::Config::CopilotAPI.hmac_secret`, which is the HMAC secret for CAPI's "github" integration group.
        ).void
      end
      def initialize(user:, integration_id: CopilotAPI::COPILOT_CHAT_INTEGRATION_ID, token: nil, hmac_secret: GitHub::Config::CopilotAPI.hmac_secret)
        @user = user
        @integration_id = integration_id
        @token = token
        @hmac_secret = hmac_secret
      end

      sig { params(prompt: String).returns(Promise[String]) }
      def async_send_platform_agent_chat_message(prompt:)
        path = "/agents/chat"
        data = { messages: [{ role: "user", content: prompt }] }
        async_make_request(method: :post, path:, data:)
      end

      sig { params(block: T.nilable(T.proc.void)).returns(Faraday::Connection) }
      memoize def async_connection(&block)
        raise CopilotAPI::Disabled if !CopilotAPI.enabled?

        ::ConcurrentFaraday.new(
          GitHub.copilot_api_internal_url,
          ssl: nil
        ) do |conn|
          conn.options[:open_timeout] = 0.250
          conn.options[:params_encoder] = Faraday::FlatParamsEncoder
          conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
          conn.headers[:content_type] = "application/json"

          conn.request(
            :retry,
            max: 3,
            interval: 0.050,
            interval_randomness: 0.5,
            backoff_factor: 1.2,
            exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
            retry_block: proc { GitHub.dogstats.increment("rest.security_center.retries") }
          )
          conn.use(::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: "security_center")
          conn.use(::GitHub::FaradayMiddleware::Resilient, name: "security_center")
          conn.use(::GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_secret)
          conn.use(::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2)
          conn.adapter :concurrent_adapter, persistent: true
        end
      end

      private

      sig { params(path: String, query: T::Hash[Symbol, T.untyped]).returns(String) }
      def append_api_version(path:, query: {})
        url = Addressable::URI.parse(path)
        query[:apiVersion] = CAPI_VERSION
        url.query_values = query
        url.to_str
      end

      # `/agents/chat` returns an event stream. This method parses the stream and returns only the LLM content,
      # stripping out the additional content added by CAPI.
      sig { params(res_body: String).returns(String) }
      def handle_agents_chat_event_stream(res_body)
        res_body.split("\n\n").each_with_object([]) do |line, acc|
          next unless line.start_with?("data:")
          new_line = line.slice(6..-1)
          next if new_line.blank?
          next if new_line.strip == "[DONE]"

          begin
            json = JSON.parse(new_line).with_indifferent_access

            if json.dig(:choices, 0, :index) == 0 && json.dig(:choices, 0, :delta, :role).blank?
              acc << json.dig(:choices, 0, :delta, :content)
            end
          rescue JSON::ParserError => err
            # This is for cases when internal format of stream is not correct json, which shouldn't happen
            Failbot.report(err)
          end
        end.join
      end

      sig do
        params(
          method: Symbol,
          path: String,
          query: T::Hash[Symbol, T.untyped], # For GET requests.
          data: T::Hash[Symbol, T.untyped], # For POST and PATCH requests.,
          retries: Integer,
        ).returns(Promise[String])
      end
      def async_make_request(method:, path:, query: {}, data: {}, retries: MAX_RETRIES)
        url = append_api_version(path:, query:)
        body = [:post, :patch].include?(method) ? data.to_json : data
        headers = {
          "Copilot-Integration-Id": integration_id,
          "X-GitHub-User": user.id,
          # Disables blackbird using both embedding and bm25 searches, and only uses embedding search
          "x-experiment-disable_hybrid_search": 1
        }

        if token
          headers[:"Authorization"] = T.must(token).authorization_header_value
        end

        T.let(async_connection.send(method, url, body, headers), # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
          ConcurrentFaraday::FutureResponse[Faraday::Response])
        .then do |res|
          begin

            # Rely on original copilot API implementation for error handling
            CopilotAPI.send(:handle_request_error, res)

            handle_agents_chat_event_stream(res.body)

          # This handles error thrown by handle_request_error
          # We do not handle ConcurrentFaraday errors here, they can be handled by caller and will
          # come back as promise rejections
          rescue CopilotAPI::RateLimitError => e
            if retries <= 0
              GitHub.dogstats.increment("rest.security_center.ratelimit_retries_exhausted")
              return Promise.new.reject(e)
            end

            retry_header = res.headers["X-Ratelimit-User-Retry-After"]&.to_f
            # If retry was returned in seconds, wait that much - othwerwise, wait 1 second
            # the header can be in the form of absolute datetime, which is not supported yet
            wait = retry_header.is_a?(Float) && retry_header > 0 ? retry_header : 1.0
            # If we got a rate limit error, sleep for the retry header value
            GitHub.dogstats.increment("rest.security_center.ratelimit_retries")
            GitHub.dogstats.distribution("rest.security_center.ratelimit_retry_wait_seconds", wait)
            sleep(wait)

            # Recursively call make_request to retry the request
            # This chains the promises together, so the final result is the result of the last request
            async_make_request(method:, path:, query:, data:, retries: retries - 1)
          end
        end
      end
    end
  end
end
