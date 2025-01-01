# typed: true
# frozen_string_literal: true

require "test_helper"

class OrcidClientTest < GitHub::TestCase
  setup do
    @original = {
      faraday_conf_block: OrcidClient.faraday_conf_block,
      orcid_host: GitHub.orcid_host,
    }

    GitHub.orcid_host = "orcid.example.com"
  end

  teardown do
    OrcidClient.faraday_conf_block = @original[:faraday_conf_block]
    GitHub.orcid_host = @original[:orcid_host]
  end

  def stub_requests
    OrcidClient.faraday_conf_block = lambda do |conn|
      conn.adapter(:test) do |stub|
        yield stub
      end
    end
  end

  def make_json_response(doc)
    [200, { "Content-type" => "application/json" }, doc.to_json]
  end

  context "oauth_url" do
    test "constructs a URL with the provided redirect URL and state" do
      with_env(ORCID_OAUTH_CLIENT_ID: "client-id") do
        client = OrcidClient.new

        url = client.oauth_url(redirect_uri: "https://example.com", state: "totally-random")

        assert_equal "https", url.scheme
        assert_equal "orcid.example.com", url.hostname
        assert_equal "/oauth/authorize", url.path
        assert_equal "client-id", url.query_values["client_id"]
        assert_equal OrcidClient::OAUTH_RESPONSE_TYPE, url.query_values["response_type"]
        assert_equal OrcidClient::OAUTH_SCOPE, url.query_values["scope"]
        assert_equal "https://example.com", url.query_values["redirect_uri"]
        assert_equal "totally-random", url.query_values["state"]
      end
    end
  end

  context "get_authenticated_identifier" do
    test "makes a request to the ORCID API with the provided code" do
      with_env(
        ORCID_OAUTH_CLIENT_ID: "client-id",
        ORCID_OAUTH_CLIENT_SECRET: "the-secret",
      ) do
        req_body = T.let(nil, T.nilable(String))

        stub_requests do |stub|
          stub.post("https://orcid.example.com/oauth/token") do |env|
            req_body = env[:body]
            make_json_response(orcid: "0000-1111-2222-3333")
          end
        end

        client = OrcidClient.new
        result = client.get_authenticated_identifier(code: "valid-code")
        result.on(
          success: ->(r) {
            assert_equal "0000-1111-2222-3333", r.identifier
            assert_equal "success", r.log_attrs["gh.orcid.token.result"]

            refute_nil req_body
            post_body = URI.decode_www_form(T.must(req_body)).to_h
            assert_equal "client-id", post_body["client_id"]
            assert_equal "the-secret", post_body["client_secret"]
            assert_equal "authorization_code", post_body["grant_type"]
            assert_equal "valid-code", post_body["code"]
          },
          failure: ->(r) { flunk "expected result to be a success: #{r.inspect}" }
        )
      end
    end

    test "properly escapes a code containing special characters" do
      req_body = T.let(nil, T.nilable(String))

      stub_requests do |stub|
        stub.post("https://orcid.example.com/oauth/token") do |env|
          req_body = env[:body]
          make_json_response(orcid: "3333-2222-1111-0000")
        end
      end

      client = OrcidClient.new
      result = client.get_authenticated_identifier(code: "special&characters\nin  here")
      result.on(
        success: ->(_) {
          refute_nil req_body
          refute_includes req_body, "special&characters"
          post_body = URI.decode_www_form(T.must(req_body)).to_h
          assert_equal "special&characters\nin  here", post_body["code"]
        },
        failure: ->(r) { flunk "expected result to be a success: #{r.inspect}" }
      )
    end

    test "returns a failed result when the connection times out" do
      stub_requests do |stub|
        stub.post("https://orcid.example.com/oauth/token") { raise Faraday::TimeoutError.new("") }
      end

      client = OrcidClient.new
      result = client.get_authenticated_identifier(code: "code")
      result.on(
        failure: ->(r) {
          assert_includes r.user_message, "too long"
          assert_equal "failure", r.log_attrs["gh.orcid.token.result"]
          assert_equal "timeout", r.log_attrs["gh.orcid.token.reason"]
        },
        success: ->(r) { flunk "expected result to be a failure: #{r.inspect}" }
      )
    end

    test "returns a failed result when the server returns a non-200 response" do
      stub_requests do |stub|
        stub.post("https://orcid.example.com/oauth/token") do
          [500, {}, "Internal server error"]
        end
      end

      client = OrcidClient.new
      result = client.get_authenticated_identifier(code: "code")
      result.on(
        failure: ->(r) {
          assert_includes r.user_message, "an error"
          assert_equal "failure", r.log_attrs["gh.orcid.token.result"]
          assert_equal "unsuccessful-response", r.log_attrs["gh.orcid.token.reason"]
          assert_equal "500", r.log_attrs["http.response.status_code"]
        },
        success: ->(r) { flunk "expected result to be a failure: #{r.inspect}" }
      )
    end

    test "returns a failed result when the server returns a non-Hash document" do
      stub_requests do |stub|
        stub.post("https://orcid.example.com/oauth/token") do
          make_json_response([1, 2, 3])
        end
      end

      client = OrcidClient.new
      result = client.get_authenticated_identifier(code: "code")
      result.on(
        failure: ->(r) {
          assert_includes r.user_message, "unexpected result"
          assert_equal "failure", r.log_attrs["gh.orcid.token.result"]
          assert_equal "not-a-hash", r.log_attrs["gh.orcid.token.reason"]
        },
        success: ->(r) { flunk "expected result to be a failure: #{r.inspect}" }
      )
    end

    test "returns a failed result when the server returns a document without an orcid identifier" do
      stub_requests do |stub|
        stub.post("https://orcid.example.com/oauth/token") do
          make_json_response(nope: "missing")
        end
      end

      client = OrcidClient.new
      result = client.get_authenticated_identifier(code: "code")
      result.on(
        failure: ->(r) {
          assert_includes r.user_message, "unexpected result"
          assert_equal "failure", r.log_attrs["gh.orcid.token.result"]
          assert_equal "missing-orcid-key", r.log_attrs["gh.orcid.token.reason"]
        },
        success: ->(r) { flunk "expected result to be a failure: #{r.inspect}" }
      )
    end
  end
end
