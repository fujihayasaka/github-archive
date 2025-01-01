# typed: false
require 'minitest/autorun'

require_relative '../lib/proto-trust-metadata-api'

class RequestHMACTest < Minitest::Test
  def setup
    @hmac_key   = "hmac_key"
    @client_id  = "hmac_client_id"
    @middleware = Proto::TrustMetadataApi::RequestHMAC.new(app, @hmac_key, @client_id)
  end

  def app
    lambda { |env| [200, {'content-type' => 'text/plain'}, ['response body']] }
  end

  def test_algorithm
    assert Proto::TrustMetadataApi::RequestHMAC::ALGORITHM, "sha256"
  end

  def test_respond_to_call
    assert_respond_to @middleware, :call
  end

  def test_request_headers
    env = { request_headers: {}, body: "request body" }
    @middleware.call(env)

    assert_equal @client_id, env[:request_headers]["X-HMAC-Client-Id"]
    assert env[:request_headers]["Request-Body-HMAC"]
    assert env[:request_headers]["Request-HMAC"]
    assert env[:body] == "request body"
    assert env[:request_headers]["Request-Body-HMAC"] == "Xdmr/12B9L+7lOPWfHUvMkdxMtBTytSG53loG7jxM1I="
  end
end
