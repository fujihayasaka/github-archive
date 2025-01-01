# typed: true
# frozen_string_literal: true

require "proto-trust-metadata-api"

module TrustMetadata
  TMA_ENDPOINT  = GitHub.trust_metadata_url
  TMA_HMAC_KEY  = GitHub.trust_metadata_hmac_key
  TMA_CLIENT_ID = GitHub.trust_metadata_client_id
  FAILBOT_APP_NAME = "trust-metadata-api-client"
  SERVICE_NAME = "trust-metadata-api"

  sig { params(repo: Repository, bundle: T.nilable(TrustMetadata::SigstoreBundle)).returns(T.untyped) }
  def self.create_attestation_by_owner_repository(repo, bundle)
    bundle = Sigstore::Bundle::V1::Bundle.decode_json(bundle.to_json)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.create_attestation_by_owner_repository(owner_id: repo.owner_id, repository_id: repo.id, bundle: bundle)
    end
  end

  sig { params(repo: Repository, subject_digest: String, before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_repository_subject_digest(repo, subject_digest, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digest(owner_id: repo.owner_id, repository_id: repo.id, subject_digest: subject_digest, before: before, after: after, per_page: per_page)
    end
  end

  sig { params(owner: T.any(Organization, User), subject_digest: String, before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_owner_subject_digest(owner, subject_digest, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digest(owner_id: owner.id, subject_digest: subject_digest, before: before, after: after, per_page: per_page)
    end
  end

  sig { params(repo: Repository, before: T.nilable(Integer), after: T.nilable(Integer), per_page: Integer).returns(T.untyped) }
  def self.list_attestation_summaries_by_repository(repo, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestation_summaries_by_repository(owner_id: repo.owner_id, repository_id: repo.id, before: before, after: after, per_page: per_page)
    end
  end

  sig { params(repo: Repository, before: T.nilable(Integer), after: T.nilable(Integer), per_page: Integer).returns(T.untyped) }
  def self.list_attestations_by_repository_summary(repo, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_repository_summary(owner_id: repo.owner_id, repository_id: repo.id, before: before, after: after, per_page: per_page)
    end
  end

  sig { params(repo: Repository, attestation_id: Integer).returns(T.untyped) }
  def self.get_attestation_summary_by_repository(repo, attestation_id:)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_attestation_summary_by_repository(owner_id: repo.owner_id, repository_id: repo.id, attestation_id: attestation_id)
    end
  end

  sig { params(repo: Repository, attestation_id: Integer).returns(T.untyped) }
  def self.get_attestation_by_repository(repo, attestation_id:)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_attestation_by_repository(owner_id: repo.owner_id, repository_id: repo.id, attestation_id: attestation_id)
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
