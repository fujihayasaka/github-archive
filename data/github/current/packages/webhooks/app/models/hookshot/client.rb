# typed: true
# frozen_string_literal: true

module Hookshot
  class Client
    DEFAULT_TIMEOUT_IN_SECONDS = 60
    UI_TIMEOUT_IN_SECONDS = 6

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
      Hookshot::Client.for_parent(parent, UI_TIMEOUT_IN_SECONDS)
    end

    def self.for_parent(parent, timeout_threshold = nil)
      host = if (PARENTS_USING_STAGING.key?(parent) || GitHub.dynamic_lab?) && GitHub.staging_hookshot_go_url.present?
        GitHub.staging_hookshot_go_url
      else
        GitHub.hookshot_go_url
      end

      options = { parent: parent }
      options[:timeout_threshold] = timeout_threshold if timeout_threshold
      self.new host, options
    end

    def initialize(host, options = {})
      @parent  = options.delete(:parent)
      @options = options.reverse_merge({
        timeout_threshold: DEFAULT_TIMEOUT_IN_SECONDS,
      })

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
      res_status, response_body = response.status, response.body.try(:strip)

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
        res_status, response_body = get path, request_args
        [res_status, JSON.parse(response_body)]
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
        res_status, response_body = get path, request_args
        [res_status, JSON.parse(response_body)]
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

        res_status, response_body = get path, request_args
        response_body = JSON.parse(response_body) if res_status == 200
        [res_status, response_body]
      end
    end

    private

    def actor
      @_actor ||= Hook::ParentAsActor.new(parent)
    end

    def get(path, params = {})
      GitHub::Timer.timeout(options[:timeout_threshold], Faraday::TimeoutError) do
        response = faraday.get path do |req|
          req.params.update params
        end
        [response.status, response.body]
      end
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
      GitHub::Timer.timeout(options[:timeout_threshold], Faraday::TimeoutError) do
        body = encode_payload ? encode_body(payload) : payload.to_json
        result = faraday.post path do |req|
          req.headers[:content_type] = encode_payload ? CONTENT_TYPE : RAW_CONTENT_TYPE
          req.body = body
          req.headers.update(payload_size_headers(payload, body))
          req.params.update params
        end
        result
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
      options = {
        url: url,
        # i hate to turn ssl verify off, but...
        # a) only hookshot is ssl
        # 2) it's only on staging, and we don't have proper certs setup yet
        ssl: { verify: false },
        request: {
          timeout: self.options[:timeout_threshold],
          open_timeout: 5,
        },
      }

      Faraday.new(options) do |b|
        b.request :url_encoded

        b.request :retry,
          max:                 2,
          interval:            0.1,
          interval_randomness: 0.5,
          backoff_factor:      1.0,
          methods:             [:get], # We only care about retrying GET
          exceptions:          [Faraday::ConnectionFailed],
          retry_block:         retry_proc
        b.use ::GitHub::FaradayMiddleware::RequestID
        b.adapter :net_http
      end
    end

    def retry_proc
      proc do |env, _, _retries, exception|
        path = env[:url].path
        log_context = {
          "gh.catalog_service" => "github/webhooks",
          "gh.request_id" => GitHub.context[:request_id],
          "exception.type" => exception.class.to_s,
          "code.filepath" => path
        }
        GitHub::logger.info(log_context)

        tags = [
          "status:#{env[:status]}",
          "method:#{env[:method]}",
          "path:#{path}",
          "exception:#{exception.class}",
        ]
        GitHub.dogstats.increment("rpc.hookshot.retries", tags: tags)
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
      start = Time.now
      tags = ["rpc_operation:#{fn}"]
      res_status, response_body = yield
    rescue Faraday::TimeoutError, Faraday::ConnectionFailed => e
      tags = T.must(tags) + ["error:#{e.class.name}"]
      GitHub.dogstats.increment("rpc.hookshot.errors", tags: tags)
      GitHub::logger.error(log_context.merge({ :exception => e, "code.namespace" => fn }))
      [500, { message: "Something went wrong." }]
    ensure
      ms = ((Time.now - T.must(start)) * 1000).round
      tags = T.must(tags) + ["status:#{res_status}"]
      GitHub.dogstats.distribution("rpc.hookshot.time", ms, tags: tags)
      GitHub.dogstats.increment("rpc.hookshot.count", tags: tags)
    end

  end
end
