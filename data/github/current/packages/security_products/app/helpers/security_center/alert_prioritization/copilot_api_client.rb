# typed: strict
# frozen_string_literal: true

module SecurityCenter
  module AlertPrioritization
    class CopilotApiClient
      extend T::Sig
      include GitHub::Memoizer

      CAPI_VERSION = "2023-07-07"
      MODEL_VERSION = "gpt-4o"

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

      sig { params(prompt: String).returns(String) }
      def send_platform_agent_chat_message(prompt:)
        path = "/agents/chat"
        data = { model: MODEL_VERSION, messages: [{ role: "user", content: prompt }] }
        res = make_request(method: :post, path:, data:)

        handle_agents_chat_event_stream(res.body)
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
            Failbot.report(err)
          end
        end.join
      end

      sig { params(blk: T.untyped).returns(::GitHub::FaradayClient::Internal) }
      memoize def connection(&blk)
        raise CopilotAPI::Disabled if !CopilotAPI.enabled?

        ::GitHub::FaradayClient::Internal.new(
          GitHub::Config::CopilotAPI.api_url,
          { ssl: nil }
        ) do |conn|
          conn.options[:open_timeout] = 0.250
          conn.headers[:user_agent] = "github-#{GitHub.role}/#{GitHub.current_sha}"
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
          conn.adapter(:typhoeus)

          yield conn if block_given?
        end
      end

      sig do
        params(
          method: Symbol,
          path: String,
          query: T::Hash[Symbol, T.untyped], # For GET requests.
          data: T::Hash[Symbol, T.untyped] # For POST and PATCH requests.
        ).returns(Faraday::Response)
      end
      def make_request(method:, path:, query: {}, data: {})
        url = append_api_version(path:, query:)
        body = [:post, :patch].include?(method) ? data.to_json : data
        headers = {
          :copilot_integration_id => integration_id,
          CopilotAPI::GITHUB_USER_HEADER => user.id
        }

        if token
          headers[:authorization] = T.must(token).authorization_header_value
        end

        raw_res = T.let(connection.send(method, url, body, headers), ::Faraday::Response) # rubocop:disable GitHub/AvoidObjectSendWithDynamicMethod
        CopilotAPI.send(:handle_request_error, raw_res)

        raw_res
      end
    end
  end
end
