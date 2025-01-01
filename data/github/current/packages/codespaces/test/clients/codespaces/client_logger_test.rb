# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesClientLoggerTest < GitHub::TestCase
  include GitHub::LoggerHelper

  class ScrubberTest < GitHub::TestCase
    setup do
      @scrubber = Codespaces::ClientLogger::Scrubber.new
    end

    context "using sensitive keys" do
      test "sensitive keys are filtered from the top level of a hash" do
        @scrubber.sensitive_keys :email
        # Make sure we leave other keys alone
        scrubbed = @scrubber.scrub(email: "hubot@github.com", repo: "avocadocorp/pits")
        assert_equal({ repo: "avocadocorp/pits", email: "[FILTERED EMAIL]" }, scrubbed)
      end

      test "sensitive keys are filtered from a nested hash" do
        @scrubber.sensitive_keys :email
        scrubbed = @scrubber.scrub(user: { email: "hubot@github.com" })
        assert_equal({ user: { email: "[FILTERED EMAIL]" } }, scrubbed)
      end
    end

    context "using sensitive data sensitive data" do
      test "sensitive data is filtered when given a string" do
        @scrubber.with_sensitive_data email: "hubot@github.com" do
          assert_equal "Hello from [FILTERED EMAIL]!", @scrubber.scrub("Hello from hubot@github.com!")
        end
      end

      test "sensitive data is filtered from the top level of a hash" do
        @scrubber.with_sensitive_data email: "hubot@github.com" do
          assert_equal({ email: "[FILTERED EMAIL]" }, @scrubber.scrub(email: "hubot@github.com"))
        end
      end

      test "sensitive data is filtered from a nested hash" do
        @scrubber.with_sensitive_data email: "hubot@github.com" do
          assert_equal({ user: { email: "[FILTERED EMAIL]" } }, @scrubber.scrub(user: { email: "hubot@github.com" }))
        end
      end
    end

    context "using filters" do
      test "filters are applied when given a string" do
        @scrubber.with_filters([/(sig=)(\w+)/, '\1[REMOVED]']) do
          assert_equal "https://some.url?sig=[REMOVED]", @scrubber.scrub("https://some.url?sig=secret")
        end
      end

      test "filters are applied at the top level of a hash" do
        @scrubber.with_filters([/(sig=)(\w+)/, '\1[REMOVED]']) do
          assert_equal({ url: "https://some.url?sig=[REMOVED]" }, @scrubber.scrub(url: "https://some.url?sig=secret"))
        end
      end

      test "filters are applied to values in nested hashes" do
        @scrubber.with_filters([/(sig=)(\w+)/, '\1[REMOVED]']) do
          assert_equal({ body: { url: "https://some.url?sig=[REMOVED]" } }, @scrubber.scrub(body: { url: "https://some.url?sig=secret" }))
        end
      end
    end
  end

  class NullScrubber < Codespaces::ClientLogger::Scrubber
    def scrub(output)
      output
    end
  end

  class FakeLogger
    attr_reader :context, :data

    def to_s
      "<FakeLogger##{object_id}>: Logs: " + context.merge(data).inspect
    end

    def json_data
      @json_data ||= Hash.new { |h, k| h[k] = GitHub::JSON.parse(data[k]) }
    end

    def log_context(context = {})
      @context = context

      yield if block_given?
    end

    alias_method :with_named_tags, :log_context

    def log(data)
      @data = data
    end

    %i(unknown fatal error warn info debug).each { |level| alias_method level, :log }
  end

  fixtures do
    @url = "https://codespaces.com"
  end

  setup do
    @logger = FakeLogger.new
    @client_logger = Codespaces::ClientLogger.new(logger: @logger, scrubber: NullScrubber.new)
  end

  context "successful request logging" do
    test "it logs appropriately" do
      request = {
        url: @url,
        request_headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "message" => "Hello world!",
          "displayMode" => "information",
          "modal" => true,
        }
      }
      response = request.merge(
        body: "",
        response_headers: {
          "VsSaaS-Request-Id" => SecureRandom.uuid,
        },
        status: 201
      )
      @client_logger.request(environment(**request))
      @client_logger.response(environment(**response))

      assert_equal "github/codespaces", @logger.context["gh.catalog_service"]
      assert_equal [], @logger.data[:previous_requests]
      assert @logger.data[:request_id]
      assert @logger.data[:faraday_request_id]
      assert @logger.data[:faraday_request_id].starts_with?(Codespaces::ClientLogger::CODESPACES_REQUEST_ID_PREFIX)
      assert_equal @url, @logger.data[:request_url]
      assert_equal "GET", @logger.data[:request_method]
      assert_equal 201, @logger.data[:response_status]

      # We don't log this data on successful requests
      refute @logger.data[:request_headers]
      refute @logger.data[:request_body]
      refute @logger.data[:response_headers]
      refute @logger.data[:response_body]
    end

    test "logs multiple requests properly" do
      request = {
        url: @url,
        request_headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "message" => "Hello world!",
          "displayMode" => "information",
          "modal" => true,
        }
      }
      response = request.merge(
        body: "",
        response_headers: {
          "VsSaaS-Request-Id" => SecureRandom.uuid,
        },
        status: 201
      )
      @client_logger.request(environment(**request))
      @client_logger.response(environment(**response))
      assert_equal [], @logger.data[:previous_requests]
      assert @logger.data[:faraday_request_id]
      first_request_id = @logger.data[:faraday_request_id]

      # Simulate a second request
      @client_logger.request(environment(**request))
      @client_logger.response(environment(**response))
      assert_equal [first_request_id], @logger.data[:previous_requests]
      assert @logger.data[:faraday_request_id]
      refute_equal first_request_id, @logger.data[:faraday_request_id]
      second_request_id = @logger.data[:faraday_request_id]

      # Simulate a third request
      @client_logger.request(environment(**request))
      @client_logger.response(environment(**response))
      assert_equal [first_request_id, second_request_id], @logger.data[:previous_requests]
    end
  end

  context "bad request logging" do
    test "it logs appropriately" do
      request = {
        url: @url,
        method: "post",
        request_headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "message" => "Hello world!",
          "displayMode" => "information",
          "modal" => true,
        }
      }
      response = request.merge(
        body: "{\"errors\":{\"environmentId\":[\"The value 'monalisa-github-public-server-pjgxw2r67' is not valid.\"]},\"type\":\"https://tools.ietf.org/html/rfc7231#section-6.5.1\",\"title\":\"One or more validation errors occurred.\",\"status\":\"400\"}",
        response_headers: {
          "Content-Type" => "application/problem+json; charset=utf-8",
          "VsSaaS-Request-Id" => SecureRandom.uuid,
        },
        status: 400
      )
      @client_logger.request(environment(**request))
      @client_logger.response(environment(**response))

      assert_equal "github/codespaces", @logger.context["gh.catalog_service"]
      assert_equal [], @logger.data[:previous_requests]
      assert @logger.data[:request_id]
      assert @logger.data[:faraday_request_id]
      assert_equal @url, @logger.data[:request_url]
      assert_equal "POST", @logger.data[:request_method]
      assert_equal 400, @logger.data[:response_status]

      # We log request/response headers and bodies on unsuccessful responses
      assert_includes @logger.data[:request_headers], "Content-Type"
      assert_includes @logger.data[:request_body], "Hello world!"
      assert_includes @logger.data[:response_headers], "Content-Type"
      assert_includes @logger.data[:response_headers], "VsSaaS-Request-Id"
      assert_includes @logger.data[:response_body], "The value 'monalisa-github-public-server-pjgxw2r67' is not valid"
    end
  end

  context "exception logging" do
    test "it logs appropriately when the exception has an embedded response" do
      request = {
        url: @url,
        method: "post",
        request_headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "message" => "Hello world!",
          "displayMode" => "information",
          "modal" => true,
        }
      }
      response = {
        body: "{\"errors\":{\"environmentId\":[\"The value 'monalisa-github-public-server-pjgxw2r67' is not valid.\"]},\"type\":\"https://tools.ietf.org/html/rfc7231#section-6.5.1\",\"title\":\"One or more validation errors occurred.\",\"status\":\"400\"}",
        headers: {
          "Content-Type" => "application/problem+json; charset=utf-8",
          "VsSaaS-Request-Id" => SecureRandom.uuid,
        },
        status: 400
      }
      @client_logger.request(environment(**request))
      @client_logger.error(Faraday::ClientError.new(response))

      assert_equal "github/codespaces", @logger.context["gh.catalog_service"]
      assert_equal [], @logger.data[:previous_requests]
      assert @logger.data[:request_id]
      assert @logger.data[:faraday_request_id]
      assert_equal @url, @logger.data[:request_url]
      assert_equal "POST", @logger.data[:request_method]
      assert_equal 400, @logger.data[:response_status]

      # We log the error and request/response headers and bodies when an error is thrown if available
      assert_equal "Faraday::ClientError", @logger.data[:request_error_class]
      assert_includes @logger.data[:request_error_message], "the server responded with status 400"
      assert_includes @logger.data[:request_headers], "Content-Type"
      assert_includes @logger.data[:request_body], "Hello world!"
      assert_includes @logger.data[:response_headers], "Content-Type"
      assert_includes @logger.data[:response_headers], "VsSaaS-Request-Id"
      assert_includes @logger.data[:response_body], "The value 'monalisa-github-public-server-pjgxw2r67' is not valid"
    end

    test "it logs appropriately when the exception has no embedded response" do
      request = {
        url: @url,
        method: "post",
        request_headers: {
          "Content-Type" => "application/json",
        },
        body: {
          "message" => "Hello world!",
          "displayMode" => "information",
          "modal" => true,
        }
      }
      response = {
        body: "{\"errors\":{\"environmentId\":[\"The value 'monalisa-github-public-server-pjgxw2r67' is not valid.\"]},\"type\":\"https://tools.ietf.org/html/rfc7231#section-6.5.1\",\"title\":\"One or more validation errors occurred.\",\"status\":\"400\"}",
        headers: {
          "Content-Type" => "application/problem+json; charset=utf-8",
          "VsSaaS-Request-Id" => SecureRandom.uuid,
        },
        status: 400
      }
      @client_logger.request(environment(**request))
      @client_logger.error(StandardError.new("BOOM"))

      assert_equal "github/codespaces", @logger.context["gh.catalog_service"]
      assert_equal [], @logger.data[:previous_requests]
      assert @logger.data[:request_id]
      assert @logger.data[:faraday_request_id]
      assert_equal @url, @logger.data[:request_url]
      assert_equal "POST", @logger.data[:request_method]

      # We log the error and leave out response details
      assert_equal "StandardError", @logger.data[:request_error_class]
      assert_includes @logger.data[:request_error_message], "BOOM"
      assert_includes @logger.data[:request_headers], "Content-Type"
      assert_includes @logger.data[:request_body], "Hello world!"
      refute @logger.data[:response_status]
      refute @logger.data[:response_headers]
      refute @logger.data[:response_body]
    end
  end

  context "catalog service" do
    test "it automatically logs the catalog service as part of the context" do
      @client_logger.log("log me")
      assert_equal({ "gh.catalog_service" => "github/codespaces" }, @logger.context)
    end
  end

  def environment(url:, method: "get", request_headers: {}, body: nil, status: 200, response_headers: {})
    Faraday::Env.from(
      method:,
      url:,
      request_headers: request_headers.reverse_merge("X-GitHub-Request-Id": SecureRandom.uuid),
      body:,
      status:,
      response_headers:
    ).tap { |env| env[:response] = Faraday::Response.new(env); env[:body] = body }
  end
end
