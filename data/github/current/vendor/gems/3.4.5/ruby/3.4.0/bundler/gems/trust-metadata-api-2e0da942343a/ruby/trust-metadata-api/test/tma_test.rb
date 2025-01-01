# typed: false
require 'minitest/autorun'
require 'vcr'
require 'webmock/minitest'
require 'net/http'
require 'yaml'
require 'pry'

require_relative "../lib/proto-trust-metadata-api"

TMA_DEV_HOST        = "http://localhost:8337"
TMA_DEV_YAML        = File.expand_path("../../config/development.yaml")
TMA_DEV_BUNDLE_PROVENANCE_JSON = "../../test/data/sigstore.js-3.0.0.bundle.json"
TMA_DEV_BUNDLE_SBOM_JSON = "../../test/data/github-attest-demo-sbom.sigstore.json"
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
    # provenance bundle test fixtures
    @provenance_bundle = Sigstore::Bundle::V1::Bundle.decode_json(File.read(TMA_DEV_BUNDLE_PROVENANCE_JSON))
    # these can be found in the parsed bundle test fixture
    @provenance_subject_digest = "sha512:7dc53d7251f012cb36fccff5d4514cf09c1ce0f8c181b857a0db24a0ae60ba82b4a8640149e51b419449f81d9f0c522f8727f482a09a3eb7a5f66b336e1031ba"
    @provenance_subject_name   = "pkg:npm/sigstore@2.2.0"
    # sbom bundle test fixtures
    @sbom_bundle = Sigstore::Bundle::V1::Bundle.decode_json(File.read(TMA_DEV_BUNDLE_SBOM_JSON))
    @sbom_subject_digest = "sha256:3e9409b2abaea0f8d85cca96c9938e4445213024db38050b3572c4903c2ade8b"
  end

  def setup_hmac_values(tma_dev_config)
    dotcom_config = JSON.parse(tma_dev_config["dotcom-auth-config"]).first

    { hmac_key: dotcom_config["keys"].first, hmac_client_id: dotcom_config["clientId"] }
  end

  def tma_test_client
    return @_test_client if @_test_client

    conn = Faraday.new(url: "#{TMA_DEV_HOST}/twirp") do |conn|
        # use the Request-HMAC middleware
        conn.use Proto::TrustMetadataApi::RequestHMAC,
          @hmac_values[:hmac_key],
          @hmac_values[:hmac_client_id]
        conn.adapter Faraday.default_adapter
      end
    @_test_client = Proto::TrustMetadataApi::V0::GitHubAPIClient.new(conn)
  end

  # Domain: github
  def test_tma_delete_attestations_by_id
    VCR.insert_cassette('delete_attestations_by_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = rand(1..5000)
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # delete the attestation
    attestation_ids = [write_resp.data&.attestation_id]
    delete_resp = tma_test_client.delete_attestations_by_id(attestation_ids: attestation_ids, owner_id: owner_id)
    assert_nil delete_resp.error, "delete response error is not nil"

    # fail to read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"
    assert_equal "no matching attestations found", read_resp.error&.msg, "response error message should be 'no matching attestations found'"
    VCR.eject_cassette('delete_attestations_by_id') unless TMA_TEST_SERVER
  end

  def test_tma_delete_attestations_by_id_with_optional_repository_id
    VCR.insert_cassette('delete_attestations_by_id_with_optional_repository_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = rand(1..5000)
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # delete the attestation
    attestation_ids = [write_resp.data&.attestation_id]
    delete_resp = tma_test_client.delete_attestations_by_id(attestation_ids: attestation_ids, owner_id: owner_id, repository_id: repository_id)
    assert_nil delete_resp.error, "delete response error is not nil"

    # fail to read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"
    assert_equal "no matching attestations found", read_resp.error&.msg, "response error message should be 'no matching attestations found'"
    VCR.eject_cassette('delete_attestations_by_id_with_optional_repository_id') unless TMA_TEST_SERVER
  end

  def test_tma_delete_attestations_by_id_fail_with_wrong_owner_id
    VCR.insert_cassette('delete_attestations_by_id_with_optional_repository_id_with_wrong_owner_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 556
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # try and fail to delete the attestation with owner ID
    attestation_ids = [write_resp.data&.attestation_id]
    delete_resp = tma_test_client.delete_attestations_by_id(attestation_ids: attestation_ids, owner_id: 123)
    assert delete_resp.error, "delete response error should not be nil"

    # try and fail to delete the attestation with owner ID and repository ID
    delete_resp = tma_test_client.delete_attestations_by_id(attestation_ids: attestation_ids, owner_id: 123, repository_id: repository_id)
    assert delete_resp.error, "delete response error should not be nil"

    # read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response should not error"

    VCR.eject_cassette('delete_attestations_by_id_with_optional_repository_id_with_wrong_owner_id') unless TMA_TEST_SERVER
  end

  def test_tma_delete_attestations_by_subject_digest
    VCR.insert_cassette('delete_attestations_by_subject_digest') unless TMA_TEST_SERVER
    # create for test
    owner_id      = rand(1..5000)
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # delete the attestation
    subject_digests = [@provenance_subject_digest]
    delete_resp = tma_test_client.delete_attestations_by_subject_digest(subject_digests: subject_digests, owner_id: owner_id)
    assert_nil delete_resp.error, "delete response error is not nil"

    # fail to read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"
    assert_equal "no matching attestations found", read_resp.error&.msg, "response error message should be 'no attestation found'"

    VCR.eject_cassette('delete_attestations_by_subject_digest') unless TMA_TEST_SERVER
  end

  def test_tma_delete_attestations_by_subject_digest_with_optional_repository_id
    VCR.insert_cassette('delete_attestations_by_subject_digest_with_optional_repository_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = rand(1..5000)
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # delete the attestation
    subject_digests = [@provenance_subject_digest]
    delete_resp = tma_test_client.delete_attestations_by_subject_digest(subject_digests: subject_digests, owner_id: owner_id, repository_id: repository_id)
    assert_nil delete_resp.error, "delete response error is not nil"

    # fail to read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"
    assert_equal "no matching attestations found", read_resp.error&.msg, "response error message should be 'no attestation found'"

    VCR.eject_cassette('delete_attestations_by_subject_digest_with_optional_repository_id') unless TMA_TEST_SERVER
  end

  def test_tma_delete_attestations_by_subject_digest_fail_with_wrong_owner_id
    VCR.insert_cassette('delete_attestations_by_subject_digest_with_optional_repository_id_with_wrong_owner_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 555
    repository_id = rand(1..5000)
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # try and fail to delete the attestation with owner ID
    subject_digests = [@provenance_subject_digest]
    delete_resp = tma_test_client.delete_attestations_by_subject_digest(subject_digests: subject_digests, owner_id: 123)
    assert delete_resp.error, "delete response error should not be nil"

    # try and fail to delete the attestation with owner ID and repository ID
    delete_resp = tma_test_client.delete_attestations_by_subject_digest(subject_digests: subject_digests, owner_id: 123, repository_id: repository_id)
    assert delete_resp.error, "delete response error should not be nil"

    # read the attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response should not error"

    VCR.eject_cassette('delete_attestations_by_subject_digest_with_optional_repository_id_with_wrong_owner_id') unless TMA_TEST_SERVER
  end

  def test_tma_write_create_attestation_by_owner_repository
    VCR.insert_cassette('create_attestation_by_owner_repository') unless TMA_TEST_SERVER
    owner_id      = 1337
    repository_id = 42
    resp          = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)

    assert_nil resp.error, "write response error is not nil"
    assert_kind_of(Integer, resp.data&.attestation_id, "attestation id is not an integer")

    VCR.eject_cassette('create_attestation_by_owner_repository') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digest
    VCR.insert_cassette('list_attestations_by_subject_digest') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 10
    repository_id = 142
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id)
    attestation = read_resp.data&.to_h&.dig(:attestations)&.first

    refute_nil read_resp.data, "response is nil"
    assert_equal "https://slsa.dev/provenance/v1", attestation&.dig(:predicate_type), "predicate_type does not match"
    assert read_resp.data&.attestations&.count > 0, "response attestation count should greater than 0"
    assert_nil read_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digest') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digest_with_predicate_type
    VCR.insert_cassette('list_attestations_by_subject_digest_with_predicate_type') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 10
    repository_id = 142

    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify there are no matching attestations
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id, predicate_type: "https://mycustomtype.dev/v2")
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"
    assert_equal "no matching attestations found", read_resp.error&.msg, "response error message should be 'no attestation found'"

    # filter by provenance and verify there is one matching attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id, predicate_type: "provenance")
    attestation = read_resp.data&.to_h&.dig(:attestations)&.first
    refute_nil read_resp.data, "response is nil"
    assert_equal "https://slsa.dev/provenance/v1", attestation&.dig(:predicate_type), "predicate_type does not match"
    assert read_resp.data&.attestations&.count > 0, "response attestation count should greater than 0"
    assert_nil read_resp.error, "response error is not nil"

    # filter by sbom and verify there is one matching attestation
    read_resp   = tma_test_client.list_attestations_by_subject_digest(subject_digest: @sbom_subject_digest, owner_id: owner_id, predicate_type: "sbom")
    attestation = read_resp.data&.to_h&.dig(:attestations)&.first
    refute_nil read_resp.data, "response is nil"
    assert_equal "https://spdx.dev/Document/v2.3", attestation&.dig(:predicate_type), "predicate_type does not match"
    assert read_resp.data&.attestations&.count > 0, "response attestation count should greater than 0"
    assert_nil read_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digest_predicate_type') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digest_pagination
    VCR.insert_cassette('list_attestations_by_subject_digest_pagination') unless TMA_TEST_SERVER
    # create for tests
    owner_id      = 12
    repository_id = 152
    5.times do
      write_resp = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify all attestations with pagination 3 per page
    page_resp = tma_test_client.list_attestations_by_subject_digest(subject_digest: @provenance_subject_digest, owner_id: owner_id, per_page: 3)

    refute_nil page_resp.data, "response is nil"
    assert_equal 3, page_resp.data&.attestations&.count, "response attestation count should be 3"
    assert page_resp.data&.page_info&.hasNextPage == true, "response has_more should be true"
    assert_nil page_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digest_pagination') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digests
    VCR.insert_cassette('list_attestations_by_subject_digests') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 486
    repository_id = 86
    # create attestations
    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read by both subject digests and confirm both attestations are returned
    digests = [@provenance_subject_digest, @sbom_subject_digest]
    read_resp   = tma_test_client.list_attestations_by_subject_digests(subject_digests: digests, owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"

    assert_equal read_resp.data&.to_h&.dig(:owner_id), owner_id, "owner_id does not match"
    assert_equal 0, read_resp.data&.to_h&.dig(:repository_id), "repository_id should be 0"
    collections = read_resp.data&.to_h&.dig(:attestations_by_subject_digest)
    assert_equal collections.count, 2, "response attestation count should greater than 0"

    assert_equal collections[0]&.dig(:subject_digest), @sbom_subject_digest, "subject_digest does not match"
    assert_equal collections[1]&.dig(:subject_digest), @provenance_subject_digest, "subject_digest does not match"
    assert_equal collections[0]&.dig(:attestations)[0]&.dig(:predicate_type), "https://spdx.dev/Document/v2.3", "predicate_type does not match https://spdx.dev/Document/v2.3"
    assert_equal collections[1]&.dig(:attestations)[0]&.dig(:predicate_type), "https://slsa.dev/provenance/v1", "predicate_type does not match https://slsa.dev/provenance/v1"
    assert_nil read_resp.error, "response error is not nil"

    # read by repository_id and confirm both attestations are returned
    read_resp   = tma_test_client.list_attestations_by_subject_digests(subject_digests: digests, owner_id: owner_id, repository_id: repository_id)
    refute_nil read_resp.data, "response is nil"

    assert_equal read_resp.data&.to_h&.dig(:owner_id), owner_id, "owner_id does not match"
    assert_equal read_resp.data&.to_h&.dig(:repository_id), repository_id, "repository_id does not match"
    collections = read_resp.data&.to_h&.dig(:attestations_by_subject_digest)
    assert_equal collections.count, 2, "response attestation count should greater than 0"

    VCR.eject_cassette('list_attestations_by_subject_digests') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digests_predicate_type_filter
    VCR.insert_cassette('list_attestations_by_subject_digests_predicate_type_filter') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 485
    repository_id = 85
    # create attestations
    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read by both subject digests and confirm both attestations are returned
    digests = [@provenance_subject_digest, @sbom_subject_digest]
    read_resp   = tma_test_client.list_attestations_by_subject_digests(subject_digests: digests, owner_id: owner_id, predicate_type: "provenance")
    refute_nil read_resp.data, "response is nil"

    assert_equal owner_id, read_resp.data&.to_h&.dig(:owner_id), "owner_id does not match"
    collections = read_resp.data&.to_h&.dig(:attestations_by_subject_digest)
    assert_equal collections.count, 1, "response attestation count should greater than 0"

    assert_equal collections[0]&.dig(:subject_digest), @provenance_subject_digest, "subject_digest does not match"
    assert_equal collections[0]&.dig(:attestations)[0]&.dig(:predicate_type), "https://slsa.dev/provenance/v1", "predicate_type does not match https://slsa.dev/provenance/v1"
    assert_nil read_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digests_predicate_type_filter') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestations_by_subject_digests_pagination
    VCR.insert_cassette('list_attestations_by_subject_digests_pagination') unless TMA_TEST_SERVER
    # create for tests
    owner_id      = 487
    repository_id = 87
    5.times do
      write_resp = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify all attestations with pagination 3 per page
    subject_digests = [@provenance_subject_digest]
    read_resp = tma_test_client.list_attestations_by_subject_digests(subject_digests: subject_digests, owner_id: owner_id, per_page: 3)

    refute_nil read_resp.data, "response is nil"
    collection = read_resp.data&.to_h&.dig(:attestations_by_subject_digest)
    refute_nil collection, "attestations_by_subject_digest is nil"
    assert read_resp.data&.page_info&.hasNextPage == true, "response has_more should be true"
    assert_nil read_resp.error, "response error is not nil"

    VCR.eject_cassette('list_attestations_by_subject_digests_pagination') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository
    VCR.insert_cassette('list_attestation_summaries_by_repository') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 11
    repository_id = 1138
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id)
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    attestation_summary   = attestation_summaries.first
    certificate_summary   = attestation_summary.dig(:certificate_summary)

    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    # attestation summary
    refute_nil attestation_summary.dig(:id), "attestation_id should not be nil"
    refute_nil attestation_summary.dig(:owner_id), "owner_id should not be nil"
    refute_nil attestation_summary.dig(:repository_id), "repository_id should not be nil"
    assert attestation_summaries.size > 0, "response attestation summaries count to have at least one element"
    assert_equal "https://slsa.dev/provenance/v1", attestation_summary.dig(:predicate_type), "predicate_type does not match"
    assert_equal 1, attestation_summary.dig(:subjects_count), "subjects_count should be 1"
    refute_nil attestation_summary.dig(:created_at), "created_at should not be nil"
    # certificate summary
    assert_equal "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", certificate_summary.dig(:run_invocation_uri), "run_invocation_uri assertion failed"
    assert_equal "d9093d4b3b99d9ee446633ac7074e43cea78c727", certificate_summary.dig(:source_repository_digest), "source_repository_digest assertion failed"

    VCR.eject_cassette('list_attestation_summaries_by_repository') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_pagination
    VCR.insert_cassette('list_attestation_summaries_by_repository_pagination') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 18
    repository_id = 4611
    5.times do
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read and verify attestations with pagination 3 per page
    page_resp3 = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, per_page: 3)
    refute_nil page_resp3.data, "response is nil"
    assert_equal 3, page_resp3.data&.attestation_summaries&.count, "response attestation count should be 3"
    assert page_resp3.data&.page_info&.hasNextPage == true, "response has_more should be true"
    assert_nil page_resp3.error, "response error is not nil"

    VCR.eject_cassette('list_attestation_summaries_by_repository_pagination') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_created_filter
    VCR.insert_cassette('list_attestation_summaries_by_repository_created_filter') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 50
    repository_id = 1145
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # try to read with a created filter that should not match
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, created: "<2022-01-01")
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"

    # try to read with a created filter that should match
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, created: "=#{Time.now.utc.to_date}")
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    assert_equal 1, attestation_summaries.size, "response attestation summaries count should be one"

    VCR.eject_cassette('list_attestation_summaries_by_repository_created_filter') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_predicate_type_filter
    VCR.insert_cassette('list_attestation_summaries_by_repository_predicate_type_filter') unless TMA_TEST_SERVER

    owner_id      = 51
    repository_id = 1499
    # create attestations
    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # read with a filter that will only return one attestation
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, predicate_type: "sbom")
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    assert_equal 1, attestation_summaries.size, "response attestation summaries count should be one"

    VCR.eject_cassette('list_attestation_summaries_by_repository_predicate_type_filter') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_subject_name_filter
    VCR.insert_cassette('list_attestation_summaries_by_repository_subject_name_filter') unless TMA_TEST_SERVER

    owner_id      = 51
    repository_id = 1423
    # store the sbom bundle
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @sbom_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # read with a filter that will return the attestation
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, subject_name: "demo")
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    assert attestation_summaries.size > 0, "response attestation summaries count should be greater than one"

    # read with a filter that will not return any attestations
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, subject_name: "some-other-subject")
    assert_nil read_resp.data, "response is not nil"
    assert read_resp.error, "response should error"

    VCR.eject_cassette('list_attestation_summaries_by_repository_subject_name_filter') unless TMA_TEST_SERVER
  end

  def test_tma_read_list_attestation_summaries_by_repository_sort_direction
    VCR.insert_cassette('list_attestation_summaries_by_repository_sort_direction') unless TMA_TEST_SERVER
    owner_id      = 53
    repository_id = 1500
    # create attestations and record attestation IDs
    attestation_ids = []
    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
      attestation_ids << write_resp.data&.attestation_id
    end

    # read with the descending sort direction specified
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, direction: 2)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    assert_equal 2, attestation_summaries.size, "response attestation summaries count should be two"
    attestation_summary = attestation_summaries[0]
    assert_equal attestation_ids[1], attestation_summary.dig(:id), "attestation summaries should be in descending order"
    attestation_summary = attestation_summaries[1]
    assert_equal attestation_ids[0], attestation_summary.dig(:id), "attestation summaries should be in descending order"

    # read with the ascending sort direction specified
    read_resp = tma_test_client.list_attestation_summaries_by_repository(owner_id: owner_id, repository_id: repository_id, direction: 1)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    attestation_summaries = read_resp.data&.to_h.dig(:attestation_summaries)
    assert_equal 2, attestation_summaries.size, "response attestation summaries count should be two"
    attestation_summary = attestation_summaries[0]
    assert_equal attestation_ids[0], attestation_summary.dig(:id), "attestation summaries should be in ascending order"
    attestation_summary = attestation_summaries[1]
    assert_equal attestation_ids[1], attestation_summary.dig(:id), "attestation summaries should be in ascending order"

    VCR.eject_cassette('list_attestation_summaries_by_repository_sort_direction') unless TMA_TEST_SERVER
  end

  def test_tma_read_get_attestation_summary_by_repository
    VCR.insert_cassette('get_attestation_summary_by_repository') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 22
    repository_id = 1342
    write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
    assert_nil write_resp.error, "write response error is not nil"

    # read and verify
    read_resp = tma_test_client.get_attestation_summary_by_repository(attestation_id: write_resp.data&.attestation_id, owner_id: owner_id, repository_id: repository_id)
    attestation_summary = read_resp.data&.to_h.dig(:attestation_summary)
    certificate_summary = read_resp.data&.to_h.dig(:certificate_summary)

    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    # attestation summary
    refute_nil attestation_summary.dig(:id), "attestation_id should not be nil"
    refute_nil attestation_summary.dig(:owner_id), "owner_id should not be nil"
    refute_nil attestation_summary.dig(:repository_id), "repository_id should not be nil"
    refute_nil attestation_summary.dig(:created_at), "created_at should not be nil"
    assert_equal attestation_summary.dig(:predicate_type), "https://slsa.dev/provenance/v1", "predicate_type missing in bundle"
    refute_empty attestation_summary.dig(:subjects), "subjects collection should not be empty"
    assert_equal attestation_summary.dig(:subjects).first.dig(:subject_name), @provenance_subject_name, "subject name did not match"
    assert_equal attestation_summary.dig(:subjects).first.dig(:subject_digest), @provenance_subject_digest, "subject digest did not match"
    # certificate summary
    assert_equal certificate_summary.dig(:run_invocation_uri), "https://github.com/sigstore/sigstore-js/actions/runs/7507343033/attempts/1", "run_invocation_uri assertion failed"
    assert_equal certificate_summary.dig(:source_repository_digest), "d9093d4b3b99d9ee446633ac7074e43cea78c727", "source_repository_digest assertion failed"
    assert_equal certificate_summary.dig(:build_config_uri), "https://github.com/sigstore/sigstore-js/.github/workflows/release.yml@refs/heads/main", "build_config_uri assertion failed"
    assert_equal certificate_summary.dig(:source_repository_uri), "https://github.com/sigstore/sigstore-js", "source_repository_uri assertion failed"

    VCR.eject_cassette('get_attestation_summary_by_repository') unless TMA_TEST_SERVER
  end

  def test_read_get_bundles_by_id
    VCR.insert_cassette('get_bundles_by_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 23
    repository_id = 1343
    attestation_ids = []
    3.times do
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
      attestation_ids << write_resp.data&.attestation_id
    end

    # fetch bundles
    read_resp = tma_test_client.get_bundles_by_id(attestation_ids: attestation_ids, owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    
    # assert bundle data matches expectations
    read_resp.data&.bundles.map do |entry|
      assert_equal owner_id, entry["owner_id"], "owner_id does not match"
      assert_equal repository_id, entry["repository_id"], "repository_id does not match"
      refute_nil entry["bundle"], "bundle is nil"
      assert attestation_ids.include?(entry["id"]), "attestation ID not found in attestation IDs recorded during write"
    end

    VCR.eject_cassette('get_bundles_by_id') unless TMA_TEST_SERVER
  end

  def test_get_repo_ids_by_attestation_id
    VCR.insert_cassette('get_repository_ids_by_attestation_id') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 24
    repository_id = 1344
    attestation_ids = []
    3.times do
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: @provenance_bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
      attestation_ids << write_resp.data&.attestation_id
    end

    # fetch bundles
    read_resp = tma_test_client.get_repository_ids_by_attestation_id(attestation_ids: attestation_ids, owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    
    # assert repos data matches expectations
    read_resp.data&.repos.each do |entry|
      assert_equal owner_id, entry["owner_id"], "owner_id does not match"
      assert_equal repository_id, entry["repository_id"], "repository_id does not match"
    end

    VCR.eject_cassette('get_repository_ids_by_attestation_id') unless TMA_TEST_SERVER
  end

  def test_get_repo_ids_by_subject_digest
    VCR.insert_cassette('get_repository_ids_by_subject_digest') unless TMA_TEST_SERVER
    # create for test
    owner_id      = 25
    repository_id = 1345
    bundles = [@provenance_bundle, @sbom_bundle]
    bundles.each do |bundle|
      write_resp    = tma_test_client.create_attestation_by_owner_repository(bundle: bundle, owner_id: owner_id, repository_id: repository_id)
      assert_nil write_resp.error, "write response error is not nil"
    end

    # fetch bundles
    read_resp = tma_test_client.get_repository_ids_by_subject_digest(subject_digests: [@sbom_subject_digest, @provenance_subject_digest], owner_id: owner_id)
    refute_nil read_resp.data, "response is nil"
    assert_nil read_resp.error, "response error is not nil"
    
    # assert repos data matches expectations
    read_resp.data&.repos.each do |entry|
      assert_equal owner_id, entry["owner_id"], "owner_id does not match"
      assert_equal repository_id, entry["repository_id"], "repository_id does not match"
    end

    VCR.eject_cassette('get_repository_ids_by_subject_digest') unless TMA_TEST_SERVER
  end
end
