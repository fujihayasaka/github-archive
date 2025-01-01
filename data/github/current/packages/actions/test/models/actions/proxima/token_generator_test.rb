# typed: true
# frozen_string_literal: true

require "test_helper"

class Actions::Proxima::TokenGeneratorTest < GitHub::TestCase
  BASE_URL = "#{GitHub.dotcom_host_protocol}://#{GitHub.dotcom_api_host_name}"

  setup do
    @app_id = "12345"
    @app_pem = OpenSSL::PKey::RSA.new(IntegrationKey::KEY_LENGTH).to_pem
    @installation_id = "56789"
    @token = "9ef7f14a-cabd-11ee-929d-637ce2a34729"

    @connection = GitHub::FaradayClient::External.new({ url: BASE_URL }) do |f|
      f.adapter Faraday.default_adapter
    end

    @generator = Actions::Proxima::TokenGenerator.new(
      connection: @connection,
      app_id: @app_id,
      app_pem: @app_pem,
      installation_id: @installation_id,
    )
  end

  context "#generate_token" do
    test "raises an error when the response wasn't successful" do
      stub_request(:post, /app\/installations\/#{@installation_id}\/access_tokens\z/)
      .to_return(status: 401, body: JSON.generate({
        message: "Bad credentials",
        documentation_url: "https://docs.github.com/graphql",
      }))

      assert_raises Actions::Proxima::WorkflowTemplatesError, match: /request failed/ do
        @generator.generate_token
      end
    end

    test "raises an error when the response couldn't be decoded" do
      stub_request(:post, /app\/installations\/#{@installation_id}\/access_tokens\z/)
      .to_return(status: 200, body: "{ nope")

      assert_raises Actions::Proxima::WorkflowTemplatesError, match: /failed to parse response/ do
        @generator.generate_token
      end
    end

    test "returns a correct token" do
      stub_request(:post, /app\/installations\/#{@installation_id}\/access_tokens\z/)
      .to_return(status: 201, body: JSON.generate({
        "expires_at": 1.hour.from_now.iso8601,
        "permissions": {},
        "token": @token,
      }))

      generated_token = @generator.generate_token

      assert_equal @token, generated_token
    end
  end
end
