# typed: true
# frozen_string_literal: true

require "test_helper"

class HookshotClientTest < GitHub::TestCase
  include GitHub::LoggerHelper
  extend T::Helpers

  self.these_tests_are_order_dependent_and_yearn_to_be_random

  setup do
    @parent = "debug-1"
    @client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent

    @member = create :user
    @org = create :organization, admins: [@member]
    @hook = create :hook, installation_target: @org
    # Existing debug delivery guid
    # This may need to be changed if the Cassette is re-recorded
    @delivery_guid = "30a336da-804f-11e5-9813-b4e9de149e9f"
  end

  teardown do
    VCR.eject_cassette
  end

  context ".for_parent" do
    test "ensure that parents using staging go to staging" do
      with_github_instance_var(:staging_hookshot_go_url, "http://staging.hookshot.test/") do
        parent = Hookshot::Client::PARENTS_USING_STAGING.keys.first
        client = Hookshot::Client.for_parent(parent)
        assert_equal client.faraday.url_prefix.to_s, GitHub.staging_hookshot_go_url
      end
    end

    test "uses staging when in a dynamic lab environment" do
      with_github_instance_var(:staging_hookshot_go_url, "http://staging.hookshot.test/") do
        GitHub.stubs(:dynamic_lab?).returns(true)
        client = Hookshot::Client.for_parent("repo-123")
        assert_equal client.faraday.url_prefix.to_s, GitHub.staging_hookshot_go_url
      end
    end

    test "uses production when staging isn't available" do
      with_github_instance_var(:staging_hookshot_go_url, nil) do
        parent = Hookshot::Client::PARENTS_USING_STAGING.keys.first
        client = Hookshot::Client.for_parent(parent)
        assert_equal client.faraday.url_prefix.to_s, GitHub.hookshot_go_url
      end
    end

    test "uses production when staging isn't available in a dynamic lab environment" do
      with_github_instance_var(:staging_hookshot_go_url, nil) do
        GitHub.stubs(:dynamic_lab?).returns(true)
        client = Hookshot::Client.for_parent("repo-123")
        assert_equal client.faraday.url_prefix.to_s, GitHub.hookshot_go_url
      end
    end

    test "uses defined timeout threshold" do
      parent = "repository-1"
      client = Hookshot::Client.for_parent(parent)
      assert_equal client.faraday.options.timeout, Hookshot::Client::DEFAULT_TIMEOUT_IN_SECONDS
    end

    test "uses production url when parent is meant for production" do
      parent = "repository-1"
      client = Hookshot::Client.for_parent(parent)
      assert_equal client.faraday.url_prefix.to_s, GitHub.hookshot_go_url
    end
  end

  context ".ui_client_for_parent" do
    test "uses lower timeout threshold" do
      parent = "repository-1"
      client = Hookshot::Client.ui_client_for_parent(parent)
      assert_equal client.faraday.options.timeout, Hookshot::Client::UI_TIMEOUT_IN_SECONDS
    end
  end

  context ".secure_token" do
    test "signs the token with sha-256" do
      token = Hookshot::Client.secure_token("abc123", 1, 12345)
      expected_token = OpenSSL::HMAC.hexdigest("sha256", GitHub.hookshot_token, "12345/abc123/1")
      assert_equal expected_token, token
    end
  end

  context "#deliver" do
    test "it sends the payload size and token headers" do
      payload = { guid: @delivery_guid, commits: "*" * 10000000 }
      payload_size = payload.to_json.bytesize

      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.post "/hooks" do |env|
            assert_equal payload_size, env.request_headers["X-GitHub-Content-Length"].to_i

            string_to_sign = [payload_size, env.body].join("/")
            token_to_compare =
              OpenSSL::HMAC.hexdigest("sha256", GitHub.hookshot_token, string_to_sign)

            assert_equal token_to_compare, env.request_headers["X-GitHub-Content-Length-Token"]
            [200, {}, ""]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)
      @client.deliver(payload)
    end

    test "it uses only zstream to encode payload when delivering to hookshot-go" do
      payload = { guid: @delivery_guid, commits: "*" * 100 }

      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.post "/hooks" do |env|
            unencoded_body = Coders.compose(Coders::ZSTREAM, default: {}).load(env.body)
            json_body = JSON.parse(unencoded_body)
            assert_equal payload[:guid], json_body["guid"]
            [200, {}, ""]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)
      assert_equal 200, @client.deliver(payload).first
    end

    test "it sends timing metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      with_stubbed_faraday_response("/hooks", [200, {}, "{}"]) do
        @client.deliver({})
        expected_tags = ["rpc_operation:deliver", "status:200"]
        assert_equal 1, GitHub.dogstats.distributions("rpc.hookshot.time", tags: expected_tags).count
      end
    end

    test "it uses hookshot_path namespace if present" do
      with_github_instance_var(:hookshot_path, "/hookshot") do
        with_stubbed_faraday_response("/hookshot/hooks", [200, {}, "{}"]) do
          assert_equal 200, @client.deliver({}).first
        end
      end
    end

    test "it does not use hookshot_path namespace if not set" do
      with_github_instance_var(:hookshot_path, nil) do
        with_stubbed_faraday_response("/hooks", [200, {}, "{}"]) do
          assert_equal 200, @client.deliver({}).first
        end
      end
    end
  end

  context "tracing" do
    test "it includes headers for logs and distributed traces" do
      handlers = @client.faraday.builder.handlers
      assert_includes handlers, ::GitHub::FaradayMiddleware::RequestID
    end
  end

  context "#deliveries_for_hook" do
    test "it gracefully handles timeouts" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      logs = T.let([], T.untyped)
      GitHub::logger.expects(:error).with { |log| logs << log }.at_least_once

      client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent
      GitHub::Timer.expects(:timeout).raises(Faraday::TimeoutError)
      status, body = client.deliveries_for_hook 1
      assert_equal 500, status
      assert_equal({ message: "Something went wrong." }, body)

      tags = ["rpc_operation:deliveries_for_hook", "error:Faraday::TimeoutError"]
      assert_equal 1, GitHub.dogstats.increments("rpc.hookshot.errors", tags: tags).count

      assert_equal(1, logs.size)
      assert_equal("github/webhooks", logs.first["gh.catalog_service"])
      assert_equal("deliveries_for_hook", logs.first["code.namespace"])
      assert_equal("app/models/hookshot/client.rb", logs.first["code.filepath"])
    end

    test "it gracefully handles connection failures" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      logs = T.let([], T.untyped)
      GitHub::logger.expects(:error).with { |log| logs << log }.at_least_once

      client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent
      client.expects(:get).raises(Faraday::ConnectionFailed, "error")
      status, body = client.deliveries_for_hook 1
      assert_equal 500, status
      assert_equal({ message: "Something went wrong." }, body)

      tags = ["rpc_operation:deliveries_for_hook", "error:Faraday::ConnectionFailed"]
      assert_equal 1, GitHub.dogstats.increments("rpc.hookshot.errors", tags: tags).count

      assert_equal(1, logs.size)
      assert_equal("github/webhooks", logs.first["gh.catalog_service"])
      assert_equal("deliveries_for_hook", logs.first["code.namespace"])
      assert_equal("app/models/hookshot/client.rb", logs.first["code.filepath"])
    end

    test "it returns the response code" do
      with_stubbed_faraday_response("/deliveries", [200, {}, {}]) do
        status, _ = @client.deliveries_for_hook 1
        assert_equal 200, status
      end
    end

    test "it returns an array of deliveries belonging to the hook" do
      body = T.let({ deliveries: [{ guid: "30a336da-804f-11e5-9813-b4e9de149e9f", delivered_at: "2020-11-16T22:19:45Z" }] }, T.untyped)
      with_stubbed_faraday_response("/deliveries", [200, {}, body]) do
        _, body = @client.deliveries_for_hook 1
        deliveries = body["deliveries"]

        assert_equal 1, deliveries.count
        assert_equal @delivery_guid, deliveries.first["guid"]
      end
    end

    test "it parses the JSON for a non-200 response" do
      expected_body = {
        "message" => "The property '#/hook_id' value \"foo\" did not match the regex '^[0-9]+$'",
      }

      with_stubbed_faraday_response("/deliveries", [400, {}, expected_body]) do
        status, body = @client.deliveries_for_hook "foo"
        assert_equal 400, status
        assert_equal expected_body, body
      end
    end

    test "it sends the parent param" do
      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.get "/deliveries" do |env|
            assert_equal @parent, env.params["parent"]
            [200, {}, "{}"]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)
      @client.deliveries_for_hook(1)
    end

    test "it sends timing metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      with_stubbed_faraday_response("/deliveries", [200, {}, "{}"]) do
        @client.deliveries_for_hook(1)
        expected_tags = ["rpc_operation:deliveries_for_hook", "status:200"]
        assert_equal 1, GitHub.dogstats.distributions("rpc.hookshot.time", tags: expected_tags).count
      end
    end

    test "it uses hookshot_path namespace if present" do
      with_github_instance_var(:hookshot_path, "/hookshot") do
        with_stubbed_faraday_response("/hookshot/deliveries", [200, {}, "{}"]) do
          assert_equal 200, @client.deliveries_for_hook(1).first
        end
      end
    end

    test "it does not use hookshot_path namespace if not set" do
      with_github_instance_var(:hookshot_path, nil) do
        with_stubbed_faraday_response("/deliveries", [200, {}, "{}"]) do
          assert_equal 200, @client.deliveries_for_hook(1).first
        end
      end
    end
  end

  context "#delivery_for_hook" do
    test "it gracefully handles timeouts" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      logs = T.let([], T.untyped)
      GitHub::logger.expects(:error).with { |log| logs << log }.at_least_once

      VCR.use_cassette("hookshot/api") do |cassette|
        Timecop.freeze(cassette.originally_recorded_at) do
          client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent
          GitHub::Timer.expects(:timeout).raises(Faraday::TimeoutError)
          status, body = client.delivery_for_hook 1, 1
          assert_equal 500, status
          assert_equal({ message: "Something went wrong." }, body)

          expected_tags = ["rpc_operation:delivery_for_hook", "error:Faraday::TimeoutError"]
          assert_equal 1, GitHub.dogstats.increments("rpc.hookshot.errors", tags: expected_tags).count

          assert_equal(1, logs.size)
          assert_equal("github/webhooks", logs.first["gh.catalog_service"])
          assert_equal("delivery_for_hook", logs.first["code.namespace"])
          assert_equal("app/models/hookshot/client.rb", logs.first["code.filepath"])
        end
      end
    end

    test "it returns the response code" do
      VCR.use_cassette("hookshot/api") do |cassette|
        Timecop.freeze(cassette.originally_recorded_at) do
          status, _ = @client.delivery_for_hook 1, 1
          assert_equal 200, status
        end
      end
    end

    test "it returns a delivery hash for the given hook_id" do
      VCR.use_cassette("hookshot/api") do |cassette|
        Timecop.freeze(cassette.originally_recorded_at) do
          _, delivery = @client.delivery_for_hook 1, 1

          assert_equal 1, delivery["id"]
        end
      end
    end

    test "it raises error when request is invalid" do
      expected_body = {
        "message" => "The property '#/hook_id' value \"foo\" did not match the regex '^[0-9]+$'",
      }

      VCR.use_cassette("hookshot/api") do |cassette|
        Timecop.freeze(cassette.originally_recorded_at) do
          status, body = @client.delivery_for_hook 1, "foo"
          assert_equal 400, status
          assert_equal expected_body, body
        end
      end
    end

    test "it sends the parent param" do
      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.get "/deliveries/123" do |env|
            assert_equal @parent, env.params["parent"]
            [200, {}, "{}"]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)
      @client.delivery_for_hook(123, 1)
    end

    test "it sends timing metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      with_stubbed_faraday_response("/deliveries/123", [200, {}, "{}"]) do
        @client.delivery_for_hook(123, 1)
        expected_tags = ["rpc_operation:delivery_for_hook", "status:200"]
        assert_equal 1, GitHub.dogstats.distributions("rpc.hookshot.time", tags: expected_tags).count
      end
    end

    test "it uses hookshot_path namespace if present" do
      with_github_instance_var(:hookshot_path, "/hookshot") do
        with_stubbed_faraday_response("/hookshot/deliveries/123", [200, {}, "{}"]) do
          assert_equal 200, @client.delivery_for_hook(123, 1).first
        end
      end
    end
  end

  context "#statuses_for_hooks" do
    test "it gracefully handles timeouts" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      logs = T.let([], T.untyped)
      GitHub::logger.expects(:error).with { |log| logs << log }.at_least_once

      client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent
      GitHub::Timer.expects(:timeout).raises(Faraday::TimeoutError)
      status, body = client.statuses_for_hooks([1])
      assert_equal 500, status
      assert_equal({ message: "Something went wrong." }, body)

      tags = ["rpc_operation:statuses_for_hooks", "error:Faraday::TimeoutError"]
      assert_equal 1, GitHub.dogstats.increments("rpc.hookshot.errors", tags: tags).count

      assert_equal(1, logs.size)
      assert_equal("github/webhooks", logs.first["gh.catalog_service"])
      assert_equal("statuses_for_hooks", logs.first["code.namespace"])
      assert_equal("app/models/hookshot/client.rb", logs.first["code.filepath"])
    end

    test "it returns the response code" do
      with_stubbed_faraday_response("/statuses", [200, {}, {}]) do
        status, _ = @client.statuses_for_hooks([1])
        assert_equal 200, status
      end
    end

    test "it returns an array of statuses belonging to the hooks" do
      body = { "1": { status: 200, response: "OK", created_at: "2020-11-16T22:19:45Z" } }
      with_stubbed_faraday_response("/statuses", [200, {}, body]) do
        _, statuses = @client.statuses_for_hooks([1])
        assert_equal JSON.parse(body.to_json), statuses
      end
    end

    test "it doesn't throw exception when body is not deflated" do
      with_stubbed_faraday_response("/statuses", [502, {}, {}]) do
        status, _ = assert_nothing_raised do
          @client.statuses_for_hooks([1])
        end

        assert_equal 502, status
      end
    end

    test "it sends the parent param" do
      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.get "/statuses" do |env|
            assert_equal @parent, env.params["parent"]
            [200, {}, "{}"]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)
      @client.statuses_for_hooks([1])
    end

    test "it sends timing metrics" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      with_stubbed_faraday_response("/statuses", [200, {}, "{}"]) do
        @client.statuses_for_hooks([1])
        expected_tags = ["rpc_operation:statuses_for_hooks", "status:200"]
        assert_equal 1, GitHub.dogstats.distributions("rpc.hookshot.time", tags: expected_tags).count
      end
    end

    test "it uses hookshot_path namespace if present" do
      with_github_instance_var(:hookshot_path, "/hookshot") do
        with_stubbed_faraday_response("/hookshot/statuses", [200, {}, "{}"]) do
          assert_equal 200, @client.statuses_for_hooks([1]).first
        end
      end
    end

    test "it does not use hookshot_path namespace if not set" do
      with_github_instance_var(:hookshot_path, nil) do
        with_stubbed_faraday_response("/statuses", [200, {}, "{}"]) do
          assert_equal 200, @client.statuses_for_hooks([1]).first
        end
      end
    end
  end

  context "error handling" do
    test "it retries connection failures" do
      GitHub.context.push(request_id: "abc-123")
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      client = Hookshot::Client.new "http://hookshot-go.test", parent: @parent

      expected_log = {
        "gh.catalog_service" => "github/webhooks",
        "gh.request_id" => "abc-123",
        "code.filepath" => "/deliveries",
        "exception.type" => "Faraday::ConnectionFailed"
      }

      assert_logged(**expected_log) do
        client.deliveries_for_hook(1)
      end
      assert_equal 2, GitHub.dogstats.increments("rpc.hookshot.retries").count

      tags = ["rpc_operation:deliveries_for_hook", "error:Faraday::ConnectionFailed"]
      assert_equal 1, GitHub.dogstats.increments("rpc.hookshot.errors", tags: tags).count
    end
  end

  def with_github_instance_var(instance_var, url, &blk)
    original_url = GitHub.instance_variable_get("@#{instance_var}")
    GitHub.instance_variable_set("@#{instance_var}", url)
    begin
      yield
    ensure
      GitHub.instance_variable_set("@#{instance_var}", original_url)
    end
  end

  def with_stubbed_faraday_response(path, response)
    # Several tests in this suite rely on VCR to receive mock
    # HTTP responses. These tests are difficult to update and
    # maintain, so this helper method provides a separate path
    # by using faraday stubs in place of VCR. Hopefully we
    # can move this entire test suite off of VCR over time.
    status, headers, body = response
    VCR.eject_cassette
    VCR.turned_off do
      faraday = Faraday.new(url: "http://example.invalid") do |f|
        f.adapter :test do |stub|
          stub.get path do |_env|
            [status, headers, body.to_json]
          end

          stub.post path do |_env|
            [status, headers, body.to_json]
          end
        end
      end

      @client.stubs(:faraday).returns(faraday)

      yield
    end
  end

  def zlib_pack(body)
    Zlib::Deflate.deflate(Mochilo.encode(body))
  end
end
