# typed: false
require 'minitest/autorun'
require 'vcr'
require 'webmock/minitest'
require 'net/http'
require 'yaml'
require 'pry'

require 'sorbet-runtime'
require_relative "../lib/proto-trust-metadata-api"

TMA_DEV_HOST        = "http://localhost:8337"
TMA_DEV_YAML        = File.expand_path("../../config/development.yaml")
TMA_DEV_BUNDLE_JSON = "../../testing/data/sigstore.js-3.0.0.bundle.json"
TMA_TEST_SERVER     = ENV.fetch('TMA_TEST_SERVER', false) # Set this to test against local TMA server

VCR.configure do |c|
  c.cassette_library_dir = 'test/cassettes'
  c.hook_into :webmock
  c.allow_http_connections_when_no_cassette = true
  # c.debug_logger
end

class TMATest < Minitest::Test
  def setup
    if TMA_TEST_SERVER
      begin
        Net::HTTP.get_response(URI("#{TMA_DEV_HOST}/status"))
      rescue Errno::ECONNREFUSED => e
        puts "Connection refused: #{e.message}"
        puts "Ensure the TMA server is running locally"
        exit 1
      end
    end

    @hmac_values = setup_hmac_values(YAML.load_file(TMA_DEV_YAML))
    @bundle      = File.read(TMA_DEV_BUNDLE_JSON)
    # this can be found in the parsed bundle test fixture
    @subject_digest = "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba"
  end

  def setup_hmac_values(tma_dev_config)
    dotcom_config = JSON.parse(tma_dev_config["dotcom-auth-config"]).first

    { hmac_key: dotcom_config["keys"].first, hmac_client_id: dotcom_config["clientId"] }
  end

  def tma_test_client
    return @_test_client if @_test_client

    conn = Proto::TrustMetadataApi::Client.connection("#{TMA_DEV_HOST}/twirp", @hmac_values[:hmac_key], @hmac_values[:hmac_client_id])
    @_test_client = Proto::TrustMetadataApi::V0::GitHubAPIClient.new(conn)
  end

  def test_tma_client_class_exists
    assert defined?(Proto::TrustMetadataApi::Client), "Proto::TrustMetadataApi::Client is not defined"
  end

  def test_tma_client_connection
    conn = Proto::TrustMetadataApi::Client.connection("#{TMA_DEV_HOST}/status", @hmac_values[:hmac_key], @hmac_values[:hmac_client_id])

    assert conn, ".connection is not defined"
    assert_instance_of(Faraday::Connection, conn, ".connection is not an instance of Faraday::Connection")
  end

  def test_tma_error
    test_error = Proto::TrustMetadataApi::Client::Error.new("test error")

    assert_instance_of(Proto::TrustMetadataApi::Client::Error, test_error, ".error is not an instance of Proto::TrustMetadataApi::Client::Error")
    assert_equal("test error", test_error.message, ".message does not return the error message")
    assert_respond_to(test_error, :error, ".error does not respond to :error")
  end

  # Domain: github
  def test_tma_write_create_attestation_by_owner_repository
    VCR.insert_cassette('create_attestation_by_owner_repository') unless TMA_TEST_SERVER
    owner_id      = 1337
    repository_id = 42
    bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
    resp          = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil resp.error, "write response error is not nil"
    assert_kind_of(Integer, resp.data&.attestation_id, "attestation id is not an integer")

    VCR.eject_cassette('create_attestation_by_owner_repository') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digest
    VCR.insert_cassette('list_attestations_by_subject_digest') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 10
    repository_id = 142
    bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @subject_digest, owner_id: owner_id)
    attestation = read_resp.data&.to_h&.dig(:attestations)&.first

    assert read_resp.data != nil, "response is nil"
    assert attestation&.dig(:predicate_type) == "https://slsa.dev/provenance/v1", "predicate_type missing in bundle"
    assert read_resp.data&.attestations&.count > 0, "response attestation count should greater than 0"
    assert_nil read_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digest') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digest_pagination
    VCR.insert_cassette('list_attestations_by_subject_digest_pagination') unless TMA_TEST_SERVER
    # create for tests
    owner_id      = 12
    repository_id = 152
    5.times do
      bundle     = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
      write_resp = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify all attestations with pagination 3 per page
    page_resp3 = tma_test_client.list_attestations_by_subject_digest(subject_digest: @subject_digest, owner_id: owner_id, per_page: 3)

    assert page_resp3.data != nil, "response is nil"
    assert page_resp3.data&.attestations&.count == 3, "response attestation count should be 3"
    assert page_resp3.data&.page_info&.hasNextPage == true, "response has_more should be true"
    assert_nil page_resp3.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digest_pagination') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_repository_summary
    VCR.insert_cassette('list_attestations_by_repository_summary') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 10
    repository_id = 1142
    bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp = tma_test_client.list_attestations_by_repository_summary(owner_id: owner_id, repository_id: repository_id)
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    attestation_summary   = attestation_summaries.first
    certificate_summary   = attestation_summary.dig(:certificate_summary)

    assert read_resp.data != nil, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    assert attestation_summaries.size > 0, "response attestation sumamries count to have at least one element"
    assert attestation_summary.dig(:predicate_type) == "https://slsa.dev/provenance/v1", "predicate_type missing in bundle"
    refute_nil attestation_summary.dig(:created_at), "created_at should not be nil"
    refute_nil attestation_summary.dig(:subject_digest), "subject_digest should not be nil"
    assert certificate_summary.dig(:run_invocation_uri) == "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", "run_invocation_uri assertion failed"
    assert certificate_summary.dig(:source_repository_digest) == "d9093d4b3b99d9ee446633ac7074e43cea78c727", "source_repository_digest assertion failed"

    VCR.eject_cassette('list_attestations_by_repository') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository
    VCR.insert_cassette('list_attestation_summaries_by_repository') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 11
    repository_id = 1138
    bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id)
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    attestation_summary   = attestation_summaries.first
    certificate_summary   = attestation_summary.dig(:certificate_summary)

    assert read_resp.data != nil, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    assert attestation_summaries.size > 0, "response attestation sumamries count to have at least one element"
    assert attestation_summary.dig(:predicate_type) == "https://slsa.dev/provenance/v1", "predicate_type missing in bundle"
    assert attestation_summary.dig(:subjects_count) == 1, "subjects_count should be 1"
    refute_nil attestation_summary.dig(:created_at), "created_at should not be nil"
    refute_nil attestation_summary.dig(:subject_digest), "subject_digest should not be nil"
    assert certificate_summary.dig(:run_invocation_uri) == "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", "run_invocation_uri assertion failed"
    assert certificate_summary.dig(:source_repository_digest) == "d9093d4b3b99d9ee446633ac7074e43cea78c727", "source_repository_digest assertion failed"

    VCR.eject_cassette('list_attestation_summaries_by_repository') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_pagination
    VCR.insert_cassette('list_attestation_summaries_by_repository_pagination') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 18
    repository_id = 4611
    5.times do
      bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify attestations with pagination 3 per page
    page_resp3 = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, per_page: 3)
    assert page_resp3.data != nil, "response is nil"
    assert page_resp3.data&.attestation_summaries&.count == 3, "response attestation count should be 3"
    assert page_resp3.data&.page_info&.hasNextPage == true, "response has_more should be true"
    assert_nil page_resp3.error, "response error is not nil"

    VCR.eject_cassette('list_attestation_summaries_by_repository_pagination') unless TMA_TEST_SERVER
  end

  def test_tma_read_get_attestation_summary_by_repository
    VCR.insert_cassette('get_attestation_summary_by_repository') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 22
    repository_id = 1342
    bundle        = Sigstore::Bundle::V1::Bundle.decode_json(@bundle)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp = tma_test_client.get_attestation_summary_by_repository(attestation_id: write_resp.data&.attestation_id, owner_id: owner_id, repository_id: repository_id)
    attestation_summary = read_resp.data&.to_h.dig(:attestation_summary)
    certificate_summary = read_resp.data&.to_h.dig(:certificate_summary)

    assert read_resp.data != nil, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    refute_nil attestation_summary.dig(:created_at), "created_at should not be nil"
    refute_nil attestation_summary.dig(:subject_digest), "subject_digest should not be nil"
    assert_equal attestation_summary.dig(:predicate_type), "https://slsa.dev/provenance/v1", "predicate_type missing in bundle"
    assert_equal certificate_summary.dig(:run_invocation_uri), "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", "run_invocation_uri assertion failed"
    assert_equal certificate_summary.dig(:source_repository_digest), "d9093d4b3b99d9ee446633ac7074e43cea78c727", "source_repository_digest assertion failed"
    assert_equal certificate_summary.dig(:build_config_uri), "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main", "build_config_uri assertion failed"
    assert_equal certificate_summary.dig(:source_repository_uri), "https://github.com/sigstore/sigstore-js", "source_repository_uri assertion failed"

    VCR.eject_cassette('get_attestation_summary_by_repository') unless TMA_TEST_SERVER
  end
end
