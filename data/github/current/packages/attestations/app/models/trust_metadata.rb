# typed: true
# frozen_string_literal: true

require "proto-trust-metadata-api"
require "sigstore-proto"

module TrustMetadata
  TMA_ENDPOINT  = GitHub.trust_metadata_url
  TMA_HMAC_KEY  = GitHub.trust_metadata_hmac_key
  TMA_CLIENT_ID = GitHub.trust_metadata_client_id
  FAILBOT_APP_NAME = "trust-metadata-api-client"
  SERVICE_NAME = "trust-metadata-api"

  EXPECTED_ERRORS = [
    :already_exists,
  ].freeze

  sig { params(repo: Repository, bundle: T.nilable(TrustMetadata::SigstoreBundle)).returns(T.untyped) }
  def self.create_attestation_by_owner_repository(repo, bundle)
    bundle = Sigstore::Bundle::V1::Bundle.decode_json(bundle.to_json)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME, expected_errors: EXPECTED_ERRORS) do
      tma_client.create_attestation_by_owner_repository(Proto::TrustMetadataApi::V0::CreateAttestationByOwnerRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, bundle: bundle))
    end
  end

  sig { params(repo: Repository, bundle: Sigstore::Bundle::V1::Bundle).returns(TwirpResponse) }
  def self.create_release_attestation(repo, bundle)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME, expected_errors: EXPECTED_ERRORS) do
      tma_client.create_release_attestation(Proto::TrustMetadataApi::V0::CreateReleaseAttestationRequest.new(owner_id: repo.owner_id, repository_id: repo.id, bundle: bundle))
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("tma.api.status", tags: ["status:#{res.status}", "rpc:create_release_attestation"])
    end
  end

  sig { params(owner_id: Integer, attestation_ids: T::Array[Integer]).returns(T.untyped) }
  def self.delete_attestations_by_owner_and_id(owner_id, attestation_ids)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.delete_attestations_by_id(Proto::TrustMetadataApi::V0::DeleteAttestationsByIdRequest.new(attestation_ids: attestation_ids, owner_id: owner_id))
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("tma.api.status", tags: ["status:#{res.status}", "rpc:delete_attestations_by_owner_and_id"])
    end
  end

  sig { params(owner_id: Integer, attestation_ids: T::Array[Integer]).returns(T.untyped) }
  def self.get_repository_ids_by_attestation_id(owner_id, attestation_ids)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_repository_ids_by_attestation_id(Proto::TrustMetadataApi::V0::GetRepositoryIdsByAttestationIdRequest.new(attestation_ids: attestation_ids, owner_id: owner_id))
    end
  end

  sig { params(repo: Repository, subject_digest: String, predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_repository_subject_digest(repo, subject_digest, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digest(Proto::TrustMetadataApi::V0::ListAttestationsBySubjectDigestRequest.new(owner_id: repo.owner_id, repository_id: repo.id, subject_digest: subject_digest, predicate_type: predicate_type, before: before, after: after, per_page: per_page))
    end
  end

  sig { params(owner: T.any(Organization, User), subject_digest: String, predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_owner_subject_digest(owner, subject_digest, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digest(Proto::TrustMetadataApi::V0::ListAttestationsBySubjectDigestRequest.new(owner_id: owner.id, subject_digest: subject_digest, predicate_type: predicate_type, before: before, after: after, per_page: per_page))
    end
  end

  sig { params(owner: T.any(Organization, User), subject_digests: T::Array[String], predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_owner_subject_digest_bulk_digests(owner, subject_digests, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digests(Proto::TrustMetadataApi::V0::ListAttestationsBySubjectDigestsRequest.new(owner_id: owner.id, subject_digests: subject_digests, predicate_type: predicate_type, before: before, after: after, per_page: per_page))
    end
  end

  sig { params(repo: Repository, before: T.nilable(Integer), after: T.nilable(Integer), per_page: Integer, direction: T.nilable(Integer), predicate_type: T.nilable(String), created: T.nilable(String), subject_name: T.nilable(String)).returns(T.untyped) }
  def self.list_attestation_summaries_by_repository(repo, before: nil, after: nil, per_page: 30, direction: 2, predicate_type: nil, created: nil, subject_name: nil)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestation_summaries_by_repository(Proto::TrustMetadataApi::V0::ListAttestationsByRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, before: before, after: after, per_page: per_page, direction: direction, predicate_type: predicate_type, created: created, subject_name: subject_name))
    end
  end

  sig { params(repo: Repository, attestation_id: Integer).returns(T.untyped) }
  def self.get_attestation_summary_by_repository(repo, attestation_id:)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_attestation_summary_by_repository(Proto::TrustMetadataApi::V0::GetAttestationSummaryByRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, attestation_id: attestation_id))
    end
  end

  sig { params(repo: Repository, attestation_id: Integer).returns(T.untyped) }
  def self.get_attestation_by_repository(repo, attestation_id:)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_attestation_by_repository(Proto::TrustMetadataApi::V0::GetAttestationByRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, attestation_id: attestation_id))
    end
  end

  sig { params(owner_id: Integer, subject_digests: T::Array[String]).returns(T.untyped) }
  def self.get_repository_ids_by_subject_digest(owner_id, subject_digests)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_repository_ids_by_subject_digest(Proto::TrustMetadataApi::V0::GetRepositoryIdsBySubjectDigestRequest.new(subject_digests: subject_digests, owner_id: owner_id))
    end
  end

  sig { params(repo: Repository, attestation_ids: T::Array[Integer]).returns(TwirpResponse) }
  def self.delete_attestations_by_id(repo, attestation_ids)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.delete_attestations_by_id(Proto::TrustMetadataApi::V0::DeleteAttestationsByIdRequest.new(owner_id: repo.owner_id, repository_id: repo.id, attestation_ids: attestation_ids))
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("tma.api.status", tags: ["status:#{res.status}", "rpc:delete_attestations_by_id"])
    end
  end

  sig { params(owner_id: Integer, repository_id: Integer, subject_digests: T::Array[String]).returns(T.untyped) }
  def self.delete_attestations_by_owner_subject_digest(owner_id, repository_id, subject_digests)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.delete_attestations_by_subject_digest(Proto::TrustMetadataApi::V0::DeleteAttestationsBySubjectDigestRequest.new(subject_digests: subject_digests, owner_id: owner_id, repository_id: repository_id))
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("tma.api.status", tags: ["status:#{res.status}", "rpc:delete_attestations_by_owner_subject_digest"])
    end
  end

  sig { params(repo: Repository, attestation_id: Integer).returns(TwirpResponse) }
  def self.delete_github_attestation_by_id(repo, attestation_id)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.delete_git_hub_attestation_by_id(Proto::TrustMetadataApi::V0::DeleteGitHubAttestationByIdRequest.new(owner_id: repo.owner_id, repository_id: repo.id, attestation_id: attestation_id))
    end

    T.let(response, TwirpResponse).tap do |res|
      GitHub.dogstats.increment("tma.api.status", tags: ["status:#{res.status}", "rpc:delete_github_attestation_by_id"])
    end
  end

  # Internal: Constructs a TMA client
  sig { returns(Faraday::Connection) }
  def self.tma_connection
    # setup the Faraday connection
    # This adds GitHub::FaradayMiddleware::RequestID & GitHub::FaradayMiddleware::TenantContext for us
    connection = GitHub::FaradayClient.internal(SERVICE_NAME, TMA_ENDPOINT) do |conn|
      # Use the TMA Request-HMAC middleware to sign the request
      conn.use Proto::TrustMetadataApi::RequestHMAC, TMA_HMAC_KEY, TMA_CLIENT_ID
      # Send actor_id, installation_id, etc to TMA via headers
      conn.use GitHub::FaradayMiddleware::RequestAnalytics

      # Increase request timeouts
      conn.options[:timeout]      = 8     # read/write timeouts set to 8 seconds
      conn.options[:open_timeout] = 0.250 # connection open timeout to 250ms
    end
  end

  # Returns a TMA client
  sig { returns(Proto::TrustMetadataApi::V0::GitHubAPIClient) }
  def self.tma_client
    Proto::TrustMetadataApi::V0::GitHubAPIClient.new(self.tma_connection)
  end
end
