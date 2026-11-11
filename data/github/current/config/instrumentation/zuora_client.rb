# typed: strict
# frozen_string_literal: true

if GitHub.billing_enabled?
  class ZuoraClientSubscriber
    sig { returns(String) }
    attr_reader :client
    sig { returns(OpenTelemetry::SDK::Trace::Tracer) }
    attr_reader :tracer

    sig { params(client: String).void }
    def initialize(client: "default")
      @client = client
      @tracer = T.let(GitHub::Telemetry.tracer("ZuoraClientSubscriber-#{client}}"), OpenTelemetry::SDK::Trace::Tracer)
    end

    # Env gives us access to
    # Request
    # :method - :get, :post, ...
    # :url    - URI for the current request; also contains GET parameters
    # :body   - POST parameters for :post/:put requests
    # :request_headers
    #
    # Response
    # :status - HTTP response status code, such as 200
    # :body   - the response body
    # :response_headers
    sig { params(name: String, start: Time, ends: Time, transaction_id: String, env: Faraday::Env).void }
    def call(name, start, ends, transaction_id, env)
      tracer.in_span("call") do |span|
        http_method = env.method.to_s.upcase
        duration = ends - start
        status = env.status
        url = env.url
        path = url.path.to_s
        path_template = env.request&.context&.dig("url.template") || "unknown"

        tags = [
          "http_method:#{http_method}",
          "status:#{status}",
          "path:#{path_template}",
          "faraday_client:#{client}"
        ] + tags_from_request_body(path, env[:request_body])

        if status.blank?
          span.add_event(
            "zuora-empty-response",
            attributes: {
              GitHub::Telemetry::Logs::SEVERITY_LEVEL => GitHub::Telemetry::Logs::Severity::INFO,
              "code.namespace" => "ZuoraClientSubscribler",
              "code.function" => "instrumentation.subscribe",
              "gh.billing.zuora_client.env" => env.inspect,
              "gh.billing.zuora_client.transaction_id" => transaction_id,
              "gh.billing.zuora_client.type" => client
            }
          )
        end

        GitHub.dogstats.timing("billing.zuora_client.request", duration.in_milliseconds, tags: tags)
        GitHub.dogstats.distribution("billing.zuora_client.response.dist.time", duration.in_milliseconds, tags: tags)
      end
    end

    private

    sig { params(path: String, request_body: T.nilable(String)).returns(T::Array[String]) }
    def tags_from_request_body(path, request_body)
      return [] unless request_body.present?

      if path.include?("/v1/action/query")
        # Find the object being queried (example: "Account" in "select * from Account where ...")
        object = request_body.match(/from (.*?) /i)&.captures&.first
        object ? ["object:#{object}"] : []
      elsif path.include?("/v1/orders")
        # Find all occurrences of "orderActions":[ ... ] and extract their contents
        order_actions_contents = request_body.scan(/"orderActions":\[(.*?)\]/).flatten
        # Find all "type" values within those contents
        types = order_actions_contents.flat_map { |content| content.scan(/"type":"(.*?)"/).flatten }.uniq
        # Create tags for each unique type
        types.map { |type| "order_action:#{type.downcase}" }
      else
        []
      end
    end
  end

  GlobalInstrumenter.subscribe("billing.zuora_client.request", ZuoraClientSubscriber.new)
  GlobalInstrumenter.subscribe("billing.zuora_client.retry_client.request", ZuoraClientSubscriber.new(client: "retry_client"))
end
