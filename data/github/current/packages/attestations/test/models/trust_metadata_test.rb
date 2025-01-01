# typed: true
# frozen_string_literal: true
require "test_helper"

class TrustMetadataTest < GitHub::TestCase
  fixtures do
    @org = create :organization, login: "octocat-org"
    @private_repo = create(:private_repository, owner: @org, name: "private-repo")
    @public_repo = create(:repository, owner: @org, name: "public-repo")

    @sample_subject_digest = "sha512:7bea9f6e7ff37f5fab0b36bf061200fff03099fd2fd696b91d04bc5e4f225eb9fd6e0cadcad54ba980f43fb352a99e8810b4e0abeb5c0ef2cf9108cd1f258b36".freeze
    @bundle_fixture = JSON.parse(Rails.root.join("test/fixtures/attestations/sigstorejs100_provenance_bundle.json").read)
    @sample_bundle = TrustMetadata::SigstoreBundle.new(@bundle_fixture).freeze
  end

  context "creating and fetching attestations by repo happy path" do
    test "can create a sigstore bundle and fetch attestations by subject digest" do
      VCR.use_cassette("trust_metadata/create_attestation_subject_digest_happy_path") do
        create_attestations(@private_repo, @sample_bundle)
        all_attestations = find_attestations_by_repo_subject_digest(@private_repo, @sample_subject_digest)
        attestation      = JSON.parse(all_attestations.first.to_json)
        refute_empty all_attestations
        assert_equal attestation["predicateType"], "https://slsa.dev/provenance/v0.2"
      end
    end

    test "can create a sigstore bundle and fetch attestations by repository" do
      VCR.use_cassette("trust_metadata/create_attestation_repository_happy_path") do
        create_attestations(@private_repo, @sample_bundle)
        all_attestations = list_attestation_summaries_by_repository(@private_repo)
        attestation      = JSON.parse(all_attestations.first.to_json)
        refute_empty all_attestations
        assert_equal attestation["predicateType"], "https://slsa.dev/provenance/v0.2"
      end
    end
  end

  context "creating and fetching attestations by org happy path" do
    test "can create a sigstore bundle and fetch attestations by subject digest" do
      VCR.use_cassette("trust_metadata/create_attestation_subject_digest_happy_path") do
        create_attestations(@private_repo, @sample_bundle)
        all_attestations = find_attestations_by_owner_subject_digest(@private_repo.owner, @sample_subject_digest)
        attestation      = JSON.parse(all_attestations.first.to_json)
        refute_empty all_attestations
        assert_equal attestation["predicateType"], "https://slsa.dev/provenance/v0.2"
      end
    end
  end

  context "getting attestations by repository" do
    test "can get an attestation by repository and id" do
      VCR.use_cassette("trust_metadata/list_attestation_summaries_by_repository_happy_path") do
        create_attestations(@private_repo, @sample_bundle)
        all_attestations = list_attestation_summaries_by_repository(@private_repo)
        refute_empty all_attestations

        attestation = all_attestations.first
        refute_nil attestation.id

        fetched_attestation = TrustMetadata.get_attestation_by_repository(@private_repo, attestation_id: attestation.id)
        assert_equal attestation.id, fetched_attestation.value.attestation.id
      end
    end
  end

  def create_attestations(repo, bundle)
    TrustMetadata.create_attestation_by_owner_repository(repo, bundle)
  end

  def find_attestations_by_repo_subject_digest(repo, subject_digest)
    response = TrustMetadata.list_attestations_by_repository_subject_digest(repo, subject_digest)
    response&.value&.attestations
  end

  def find_attestations_by_owner_subject_digest(owner, subject_digest)
    response = TrustMetadata.list_attestations_by_owner_subject_digest(owner, subject_digest)
    response&.value&.attestations
  end

  def list_attestation_summaries_by_repository(repo)
    response = TrustMetadata.list_attestation_summaries_by_repository(repo)
    response&.value&.attestation_summaries
  end
end
