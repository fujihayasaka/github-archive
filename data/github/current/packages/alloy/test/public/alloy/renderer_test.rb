# typed: strict
# frozen_string_literal: true

require "test_helper"

class AlloyRendererTest < GitHub::TestCase
  include Alloy::StubHelper
  include DogstatsTestHelpers

  context ".render sync" do
    test "sends HMAC header" do
      expected_ssr_content = "<div>ssr content</div>"
      with_stubbed_renderer(content: expected_ssr_content) do
        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal 200, response.status
        assert_equal expected_ssr_content, response.result
        assert_nil response.error
      end
    end

    test "send metadata to alloy and datadog" do
      expected_ssr_content = "<div>ssr content</div>"
      with_stubbed_renderer(content: expected_ssr_content) do
        response = Alloy::SyncRenderer.new(
          request: build_request,
          metadata: {
            controller: "issues",
            action: "index",
            referrer_controller: "issues",
            referrer_action: "index",
            catalog_service: "github/issues"
          }
        ).render
        assert_equal 200, response.status
        assert_equal expected_ssr_content, response.result
        assert_nil response.error

        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["controller:issues"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["action:index"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["referrer_controller:issues"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["referrer_action:index"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["catalog_service:github/issues"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["tier:#{Alloy::SelectiveSsr::Tiers::TIER_0}"]).count
      end
    end

    test "do not send metadata to alloy and datadog" do
      expected_ssr_content = "<div>ssr content</div>"
      with_stubbed_renderer(content: expected_ssr_content) do
        response = Alloy::SyncRenderer.new(
          request: build_request,
        ).render
        assert_equal 200, response.status
        assert_equal expected_ssr_content, response.result
        assert_nil response.error

        assert_equal 0, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["controller:issues"]).count
        assert_equal 0, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["action:index"]).count
        assert_equal 0, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["referrer_controller:issues"]).count
        assert_equal 0, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["referrer_action:index"]).count
        assert_equal 0, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["catalog_service:github/issues"]).count
        assert_equal 1, GitHub.dogstats.distributions("alloy.gh.render.time", tags: ["tier:#{Alloy::SelectiveSsr::Tiers::TIER_0}"]).count
      end
    end

    test "Handles HTML response" do
      expected_ssr_content = "<div>ssr content</div>"
      with_stubbed_renderer(content: expected_ssr_content) do
        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal 200, response.status
        assert_equal expected_ssr_content, response.result
        assert_nil response.error
        assert_nil response.preloaded_queries
      end
    end

    test "Handles JSON response and sets preloaded queries" do
      expected_ssr_content = "<div>ssr content</div>"
      preloaded_query = {
        queryId: "id",
        variables: {
          repo: "github",
        },
        result: {
          data: {
            repository: {
              name: "github",
            },
          },
        },
      }
      with_stubbed_json_renderer(content: expected_ssr_content, preloaded_queries: [preloaded_query]) do
        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal 200, response.status
        assert_equal expected_ssr_content, response.result
        # keys become strings when parsing from JSON
        assert_equal response.preloaded_queries, [preloaded_query.deep_stringify_keys]
        assert_nil response.error
      end
    end

    test "handles failed render" do
      with_renderer_error do
        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal 500, response.status
        assert_equal "", response.result
        assert_equal "An error occurred", response.error
        assert_equal "UTF-8", T.must(response.error).encoding.name
      end
    end

    test "reports errors" do
      with_renderer_error(status: 418, error: "I'm a Teapot") do
        GitHub.logger.stubs(:warn).returns(true)
        GitHub.logger.expects(:warn).with(
          "Alloy render call failed", {
            "code.namespace": "Alloy::SyncRenderer",
            "code.function": :render,
            "http.status_code": 418,
            "http.url": "/",
            "exception.message": "I'm a Teapot"
          }
        )

        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal 418, response.status
        assert_equal "", response.result
        assert_equal "I'm a Teapot", response.error
      end
    end

    test "doesn't render errors in production" do
      GitHub::AppEnvironment.stubs(:development?).returns(false) do
        with_renderer_error do
          response = Alloy::SyncRenderer.new(request: build_request).render
          assert_equal 500, response.status
          assert_equal "", response.result
          assert_nil response.error
        end
      end
    end

    test "encode response" do
      with_stubbed_renderer(content: "<div></div>".b.force_encoding("ASCII-8BIT")) do
        response = Alloy::SyncRenderer.new(request: build_request).render
        assert_equal "UTF-8", response.result&.encoding&.name
      end
    end
  end

  context "async" do
    test "doesn't send request when payload too large" do
      big_string = "a" * (Alloy::BaseRenderer::MAX_SIZE + 1)

      with_stubbed_manifest do
        stubs = stub_faraday(status: 500, content: "Err")

        GitHub.logger.stubs(:warn).returns(true)
        GitHub.logger.expects(:warn).with(
          "Alloy render call failed",
          {
            "code.namespace": "Alloy::AsyncRenderer",
            "code.function": :render,
            "http.status_code": 413,
            "http.url": "/",
            "exception.message": "Payload Too Large"
          }
        )

        promise = Alloy::AsyncRenderer.new(request: { name: "test", tier: Alloy::SelectiveSsr::Tiers::TIER_0, payload: { big_string: big_string }, path: "/" }).render
        response = Alloy::Response::from_faraday_response(promise.sync)
        assert_equal 413, response.status
        assert_equal "", response.result
        assert_equal "Payload too large", response.error

        stubs.expects(:post).never
      end
    end
  end

  sig { returns(T::Hash[Symbol, T.untyped]) }
  def build_request
    { name: "test", tier: Alloy::SelectiveSsr::Tiers::TIER_0, payload: {}, path: "/" }
  end
end
