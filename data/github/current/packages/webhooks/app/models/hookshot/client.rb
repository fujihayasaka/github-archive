# typed: true
# frozen_string_literal: true

module Hookshot
  class Client
    SERVICE_NAME = "hookshot-go"
    CONTENT_TYPE = "application/vnd.hookshot+zpack"
    RAW_CONTENT_TYPE = "application/vnd.hookshot+json"
    PARENTS_USING_STAGING = {
      "repository-7550011" => "github/hookshot",
      "repository-75867826"  => "api-playground/hookshot-staging",
      "repository-299429642" => "api-playground/big_boy_staging",
      "repository-775204458" => "api-playground/events-v2-staging"
    }.freeze

    attr_reader :options, :faraday, :parent

    def self.secure_token(guid, hook_id, expires)
      OpenSSL::HMAC.hexdigest("sha256", GitHub.hookshot_token, "%d/%s/%s" % [
        expires, guid, hook_id])
    end

    def self.ui_client_for_parent(parent, user = nil)
      for_parent(parent)
    end

    def self.for_parent(parent)
      host = if (PARENTS_USING_STAGING.key?(parent) || GitHub.dynamic_lab?) && GitHub.staging_hookshot_go_url.present?
        GitHub.staging_hookshot_go_url
      else
        GitHub.hookshot_go_url
      end

      new(host, parent: parent)
    end

    def initialize(host, options = {})
      @parent  = options.delete(:parent)
      @options = options
      @faraday = build_faraday(host)
    end

    # Do an HTTP POST to Hookshot's `/hooks` API. This is only used for
    # webhook payloads that are too big to fit into Aqueduct.
    def deliver(payload)
      start = Time.now
      path = File.join(String(GitHub.hookshot_path), "/hooks")
      payload = payload.with_indifferent_access
      delivery_guid = payload[:guid]

      expires = 1.minute.from_now.to_i

      response = post(path,
                      payload,
                      { token: Hookshot::Client.secure_token(delivery_guid, :delivery, expires),
                        expires: expires },
                        encode_payload: true,
                      )
      res_status, response_body = response.status, response.body

      [res_status, response_body]
    ensure
      ms = ((Time.now - T.must(start)) * 1000).round
      tags = ["rpc_operation:deliver", "status:#{res_status}"]
      GitHub.dogstats.distribution("rpc.hookshot.time", ms, tags: tags)
      GitHub.dogstats.increment("rpc.hookshot.count", tags: tags)
    end

    def deliveries_for_hook(hook_id, params = {})
      with_exception_handling_and_metrics("deliveries_for_hook") do
        path = File.join(String(GitHub.hookshot_path), "/deliveries")
        expires = 2.minutes.from_now.to_i
        token = Hookshot::Client.secure_token(params.with_indifferent_access["guid"], hook_id, expires)
        request_args = params.merge(hook_id: hook_id, token: token, expires: expires, parent: parent)
        get path, request_args
      end
    end

    def filter_deliveries_data(data, now)
      return data unless data && data["deliveries"]
      deliveries = data["deliveries"]
      # remove deliveries older than 30 days
      deliveries = deliveries.filter { |x| Time.parse(x["delivered_at"]) > (now - 30.days) }

      # exclude id since it's the primary key, which is different between
      # clusters, and delivered_at since there's a race condition there
      deliveries.map { |x| x.except("id", "delivered_at") }
    end

    def delivery_for_hook(delivery_id, hook_id, params = {})
      with_exception_handling_and_metrics("delivery_for_hook") do
        path = File.join(String(GitHub.hookshot_path), "/deliveries/#{delivery_id}")
        expires = 2.minutes.from_now.to_i
        token = Hookshot::Client.secure_token(params.with_indifferent_access["guid"], hook_id, expires)
        request_args = params.merge(hook_id: hook_id, token: token, expires: expires, parent: parent)
        get path, request_args
      end
    end

    def statuses_for_hooks(hook_ids)
      with_exception_handling_and_metrics("statuses_for_hooks") do
        path = File.join(String(GitHub.hookshot_path), "/statuses")
        expires = 1.minute.from_now.to_i
        request_args = { hook_ids: hook_ids.join(","),
                        token: Hookshot::Client.secure_token(nil, nil, expires),
                        expires: expires,
                        parent: parent }
        get path, request_args
      end
    end

    private

    def actor
      @_actor ||= Hook::ParentAsActor.new(parent)
    end

    def get(path, params = {})
      response = faraday.get(path, params)
      [response.status, response.body]
    end

    def payload_size_headers(full_payload, encoded_payload)
      size = full_payload.to_json.bytesize
      string_to_sign = [size, encoded_payload].join("/")
      token = OpenSSL::HMAC.hexdigest("sha256", GitHub.hookshot_token, string_to_sign)
      {
        "X-GitHub-Content-Length" => size.to_s,
        "X-GitHub-Content-Length-Token" => token,
      }
    end

    def post(path, payload, params = {}, encode_payload:)
      body = encode_payload ? encode_body(payload) : payload.to_json
      faraday.post(path) do |req|
        req.body = body
        req.headers[:content_type] = encode_payload ? CONTENT_TYPE : RAW_CONTENT_TYPE
        req.headers.update(payload_size_headers(payload, body))
        req.params.update(params)
      end
    end

    def encode_body(payload)
      # Log the bytesize of the raw payload before encoding it
      action = payload["payload"] && payload["payload"]["action"] ? payload["payload"]["action"] : nil
      event_type = payload["event"]
      event_tag = "#{event_type}"
      event_tag += "_#{action}" if action
      tags = ["event:#{event_tag}", "event_type:#{event_type}"]
      payload_json = payload.to_json

      GitHub.dogstats.distribution("hooks.raw_payload_size", payload_json.bytesize, tags: tags)

      GitHub.dogstats.distribution_time("hooks.time", tags: tags + ["operation:encode_payload"]) do
        serializer.dump(payload_json).tap do |encoded|
          GitHub.dogstats.distribution("hooks.payload_size", encoded.size, tags: tags)
        end
      end
    end

    def serializer
      @serializer ||= Coders.compose(Coders::ZSTREAM, default: {})
    end

    def build_faraday(url)
      GitHub::FaradayClient.internal(SERVICE_NAME, url, options) do |b|
        b.request :url_encoded
        b.use GitHub::FaradayMiddleware::Retries,
          methods:             [:get, :post],
          retry_statuses:      [429, 500, 502, 503, 504]
        b.use GitHub::FaradayMiddleware::Resilient,
          options: {
            request_volume_threshold: 10
          }
        b.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
        b.response :json, content_type: /\bjson\z/
      end
    end

    def log_context
      @log_context ||= {
        "code.filepath" => "app/models/hookshot/client.rb",
        "gh.catalog_service" => "github/webhooks",
        "gh.request_id" => GitHub.context[:request_id]
      }
    end

    def with_exception_handling_and_metrics(fn)
      tags = ["rpc_operation:#{fn}"]
      res_status, response_body = yield
    rescue => e
      tags = T.must(tags) + ["error:#{e.class.name}"]
      GitHub.dogstats.increment("rpc.hookshot.errors", tags: tags)
      GitHub::logger.error("hookshot-go client error", log_context.merge({ "exception" => e, "code.namespace" => fn }))
      [500, { message: "Something went wrong." }]
    end
  end
end
