# typed: true
require 'minitest/autorun'
require 'vcr'
require 'webmock/minitest'
require 'net/http'
require 'yaml'
require 'pry'

require_relative "../lib/monolith-twirp-attester"

ATTESTER_DEV_HOST        = "http://localhost:8338"
ATTESTER_DEV_YAML        = File.expand_path("../../config/development.yaml")
ATTESTER_DEV_RELEASE_STMT_JSON = "../../example/release_statement_03_06_2025.json"
ATTESTER_TEST_SERVER     = ENV.fetch('ATTESTER_TEST_SERVER', false) # Set this to disable VCR and run against a live server
ATTESTER_HMAC_KEY        = "dotcomsecretkey"

VCR.configure do |c|
  c.cassette_library_dir = 'test/cassettes'
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = true
end

class AttesterTest < Minitest::Test
  def setup
    if ATTESTER_TEST_SERVER
      begin
        Net::HTTP.get_response(URI("#{ATTESTER_DEV_HOST}/status"))
      rescue Errno::ECONNREFUSED => e
        puts "Connection refused: #{e.message}"
        puts "Ensure the Attester server is running locally"
        exit 1
      end
    end

    @hmac_values = { hmac_key: ATTESTER_HMAC_KEY }
    @release_statement = File.read(ATTESTER_DEV_RELEASE_STMT_JSON)
  end

  def conn
    Faraday.new(url: "#{ATTESTER_DEV_HOST}/twirp") do |conn|
      conn.use MonolithTwirp::Attester::RequestHMAC, @hmac_values[:hmac_key]
      conn.adapter Faraday.default_adapter
    end
  end

  def attester_boo_client
    return @_boo_client if @_boo_client
    @_boo_client = MonolithTwirp::Attester::V0::BooAPIClient.new(conn)
  end

  def attester_release_client
    return @_release_client if @_release_client
    @_release_client = MonolithTwirp::Attester::V0::ReleaseAPIClient.new(conn)
  end

  # Service: Boo
  def test_boo_name_request
    VCR.insert_cassette('boo_name_request') unless ATTESTER_TEST_SERVER
    name = 'Mona'
    resp = attester_boo_client.hello_name(name: name)

    assert_nil resp.error, "write response error is not nil"
    refute_nil resp.data, "response data is nil"
    assert_kind_of(String, resp.data&.message, "message is not a string")
    assert_equal resp.data.message, "Hello, Mona!", "response message incorrect"
    VCR.eject_cassette('boo_name_request') unless ATTESTER_TEST_SERVER
  end

  def test_boo_error_request
    VCR.insert_cassette('boo_error_request') unless ATTESTER_TEST_SERVER
    name = 'Mona'
    resp = attester_boo_client.error(name: name)

    refute_nil resp.error, "write response error is nil"
    assert_equal resp.error.msg, "raised exception", "response message incorrect"
    VCR.eject_cassette('boo_error_request') unless ATTESTER_TEST_SERVER
  end

  # Service: Release
  def test_release_create_release_attestation
    VCR.insert_cassette('release_create_release_attestation_request') unless ATTESTER_TEST_SERVER
    
    # NOTE: The protobuf-generated Ruby code does not account for the
    # `json_name` annotation on the `type` field. As a result, we can't properly
    # decode the JSON into a `Statement` object. We need to use the
    # `ignore_unknown_fields: true` option to avoid raising an error when the
    # `_type` field is encountered. The `type` field should be set directly to
    # ensure that the correct value is transmitted.
    statement = InTotoAttestation::V1::Statement.decode_json(@release_statement, ignore_unknown_fields: true)
    statement.type = 'https://in-toto.io/Statement/v1'

    resp = attester_release_client.create_release_attestation(statement: statement)

    assert_nil resp.error, "write response error is not nil"
    refute_nil resp.data, "response data is nil"

    bundle = resp.data.bundle
    refute_nil bundle, "bundle is nil"
    assert_kind_of(Sigstore::Bundle::V1::Bundle, bundle, "bundle is not the correct type")
    assert_equal bundle.media_type, "application/vnd.dev.sigstore.bundle.v0.3+json", "media type is incorrect"
    VCR.eject_cassette('release_create_release_attestation_request') unless ATTESTER_TEST_SERVER
  end
end
