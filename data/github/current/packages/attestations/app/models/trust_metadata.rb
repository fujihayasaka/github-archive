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

  sig { params(repo: Repository, subject_digest: String).returns(T.untyped) }
  def self.list_attestations_by_repository_and_subject_digest(repo, subject_digest)
    filters = Proto::TrustMetadataApi::V0::AttestationFilters.new(
      repository_id: repo.id,
      subject_digests: [subject_digest]
    )
    request = Proto::TrustMetadataApi::V0::ListAttestationsRequest.new(
      owner_id: repo.owner_id,
      filters: filters,
      enrichments: [Enrichment::ATTESTATION_ENRICHMENT_CERTIFICATE_SUMMARY]
    )

    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME, expected_errors: EXPECTED_ERRORS) do
      tma_client.list_attestations(request)
    end
  end

  sig { params(repo: Repository, bundle: T.nilable(TrustMetadata::SigstoreBundle)).returns(T.untyped) }
  def self.create_attestation_by_owner_repository(repo, bundle)
    bundle = Sigstore::Bundle::V1::Bundle.decode_json(bundle.to_json)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME, expected_errors: EXPECTED_ERRORS) do
      tma_client.create_attestation_by_owner_repository(Proto::TrustMetadataApi::V0::CreateAttestationByOwnerRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, bundle: bundle))
    end
  end

  sig { params(repo: Repository, bundle: Sigstore::Bundle::V1::Bundle).returns(TwirpResponse) }
  def self.create_release_attestation(repo, bundle)
    raw_resp = T.let(nil, T.untyped)
    response = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME, expected_errors: EXPECTED_ERRORS) do
      raw_resp = tma_client.create_release_attestation(Proto::TrustMetadataApi::V0::CreateReleaseAttestationRequest.new(owner_id: repo.owner_id, repository_id: repo.id, bundle: bundle))
    end

    # If TMA returned 409 (already_exists) with an attestation_id in the error
    # meta, convert to a success response. This handles the case where the caller
    # previously created the attestation but crashed before recording the ID,
    # causing a retry to hit the duplicate error.
    if response.status == 409 && (existing_id = raw_resp&.error&.meta&.[]("attestation_id"))
      proto = Proto::TrustMetadataApi::V0::CreateReleaseAttestationResponse.new(attestation_id: Integer(existing_id))
      response = TwirpResponse.new(status: 200, value: proto, call_succeeded: true)
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

  sig { params(owner: T.any(Organization, User), predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.get_repository_ids_by_owner(owner, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_repository_ids_by_owner(Proto::TrustMetadataApi::V0::GetRepositoryIdsByOwnerRequest.new(owner_id: owner.id, predicate_type: predicate_type, before: before, after: after, per_page: per_page))
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

  sig do
    params(
      owner_id: Integer,
      subject_digest: String,
      predicate_type: T.nilable(String),
      before: T.nilable(Integer),
      after: T.nilable(Integer),
      per_page: T.nilable(Integer),
      repository_id: T.nilable(Integer)
    ).returns(T.untyped)
  end
  def self.list_attestation_blob_uris(owner_id:, subject_digest:, predicate_type: nil, before: nil, after: nil, per_page: 30, repository_id: nil)
    filters_kwargs = {
      subject_digests: [subject_digest],
      predicate_type: predicate_type,
    }
    filters_kwargs[:repository_id] = repository_id if repository_id

    filters = Proto::TrustMetadataApi::V0::AttestationFilters.new(**filters_kwargs)

    request = Proto::TrustMetadataApi::V0::ListAttestationsRequest.new(
      owner_id: owner_id,
      filters: filters,
      enrichments: [Enrichment::ATTESTATION_ENRICHMENT_SAS_URL],
      before: before,
      after: after,
      per_page: per_page
    )

    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations(request)
    end
  end

  def self.list_attestation_blob_uris_by_owner_subject_digest(owner, subject_digest, predicate_type: nil, before: nil, after: nil, per_page: 30)
    list_attestation_blob_uris(
      owner_id: owner.id,
      subject_digest: subject_digest,
      predicate_type: predicate_type,
      before: before,
      after: after,
      per_page: per_page
    )
  end

  sig { params(repo: Repository, subject_digest: String, predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestation_blob_uris_by_repository_subject_digest(repo, subject_digest, predicate_type: nil, before: nil, after: nil, per_page: 30)
    list_attestation_blob_uris(
      owner_id: repo.owner_id,
      subject_digest: subject_digest,
      predicate_type: predicate_type,
      before: before,
      after: after,
      per_page: per_page,
      repository_id: repo.id
    )
  end

  sig { params(owner: T.any(Organization, User), subject_digests: T::Array[String], predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.list_attestations_by_owner_subject_digest_bulk_digests(owner, subject_digests, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations_by_subject_digests(Proto::TrustMetadataApi::V0::ListAttestationsBySubjectDigestsRequest.new(owner_id: owner.id, subject_digests: subject_digests, predicate_type: predicate_type, before: before, after: after, per_page: per_page))
    end
  end

  sig { params(owner: T.any(Organization, User), subject_digests: T::Array[String], predicate_type: T.nilable(String), before: T.nilable(Integer), after: T.nilable(Integer), per_page: T.nilable(Integer)).returns(T.untyped) }
  def self.get_attestation_identifiers_by_subject_digest(owner, subject_digests, predicate_type: nil, before: nil, after: nil, per_page: 30)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.get_attestation_identifiers_by_subject_digest(
        Proto::TrustMetadataApi::V0::GetAttestationIdentifiersBySubjectDigestRequest.new(
          owner_id: owner.id,
          subject_digests: subject_digests,
          predicate_type: predicate_type,
          before: before,
          after: after,
          per_page: per_page
        )
      )
    end
  end

  sig { params(repo: Repository, before: T.nilable(Integer), after: T.nilable(Integer), per_page: Integer, direction: T.nilable(Integer), predicate_type: T.nilable(String), created: T.nilable(String), subject_name: T.nilable(String)).returns(T.untyped) }
  def self.list_attestation_summaries_by_repository(repo, before: nil, after: nil, per_page: 30, direction: 2, predicate_type: nil, created: nil, subject_name: nil)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestation_summaries_by_repository(Proto::TrustMetadataApi::V0::ListAttestationsByRepositoryRequest.new(owner_id: repo.owner_id, repository_id: repo.id, before: before, after: after, per_page: per_page, direction: direction, predicate_type: predicate_type, created: created, subject_name: subject_name))
    end
  end

  # Thin wrapper for the unified ListAttestations endpoint.
  sig { params(request: Proto::TrustMetadataApi::V0::ListAttestationsRequest).returns(T.untyped) }
  def self.list_attestations(request)
    TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
      tma_client.list_attestations(request)
    end
  end

  # Short alias for the verbose Proto enrichment enum module.
  Enrichment = Proto::TrustMetadataApi::V0::AttestationEnrichment

  # Sort direction constants matching Proto enum values.
  SORT_DIRECTION_ASC = 1
  SORT_DIRECTION_DESC = 2

  # Lists attestations for a repository using the ListAttestations endpoint.
  sig do
    params(
      repo: Repository,
      enrichments: T::Array[Integer],
      before: T.nilable(Integer),
      after: T.nilable(Integer),
      per_page: Integer,
      direction: T.nilable(Integer),
      predicate_type: T.nilable(String),
      created: T.nilable(String),
      subject_name: T.nilable(String),
      include_count: T::Boolean,
      initiator: T.nilable(String)
    ).returns(T.untyped)
  end
  def self.list_attestations_by_repository(
    repo,
    enrichments:,
    before: nil,
    after: nil,
    per_page: 30,
    direction: SORT_DIRECTION_DESC,
    predicate_type: nil,
    created: nil,
    subject_name: nil,
    include_count: false,
    initiator: nil
  )
    filters = Proto::TrustMetadataApi::V0::AttestationFilters.new(
      repository_id: repo.id,
      predicate_type: predicate_type,
      subject_name: subject_name,
      created: timestamp_range_for_day(created),
      initiator: initiator
    )

    request = Proto::TrustMetadataApi::V0::ListAttestationsRequest.new(
      owner_id: repo.owner_id,
      filters: filters,
      enrichments: enrichments,
      before: before,
      after: after,
      per_page: per_page,
      sort_direction: sort_direction(direction),
      include_count: include_count
    )

    list_attestations(request)
  end

  # Converts integer direction to Proto SortDirection enum value.
  # Defaults to DESC if direction is nil or unrecognized.
  sig { params(direction: T.nilable(Integer)).returns(Integer) }
  def self.sort_direction(direction)
    case direction
    when SORT_DIRECTION_ASC
      Proto::TrustMetadataApi::V0::SortDirection::SORT_DIRECTION_ASC
    else
      Proto::TrustMetadataApi::V0::SortDirection::SORT_DIRECTION_DESC
    end
  end

  # Converts a date string (optionally prefixed with an operator) to a TimestampRange.
  #
  # AttestationsQueryHelper normalizes date filters into operator-prefixed strings:
  #   "=2026-01-15"  → full day range (beginning_of_day..end_of_day)
  #   ">=2026-01-15" → open-ended range from beginning_of_day onward
  #   ">2026-01-15"  → open-ended range after end_of_day
  #   "<=2026-01-15" → open-ended range up through end_of_day
  #   "<2026-01-15"  → open-ended range before beginning_of_day
  #   "2026-01-15"   → treated as "=" (full day range)
  #
  # Returns nil if the input is blank or invalid.
  sig { params(date_string: T.nilable(String)).returns(T.nilable(Proto::TrustMetadataApi::V0::TimestampRange)) }
  def self.timestamp_range_for_day(date_string)
    return nil if date_string.blank?

    operator, raw_date = parse_date_operator(date_string)

    date = Time.find_zone!("UTC").parse(raw_date)
    return nil if date.nil?

    range_args = case operator
    when "="
      {
        after: Google::Protobuf::Timestamp.new(seconds: date.beginning_of_day.to_i),
        before: Google::Protobuf::Timestamp.new(seconds: date.end_of_day.to_i),
      }
    when ">="
      { after: Google::Protobuf::Timestamp.new(seconds: date.beginning_of_day.to_i) }
    when ">"
      { after: Google::Protobuf::Timestamp.new(seconds: date.end_of_day.to_i) }
    when "<="
      { before: Google::Protobuf::Timestamp.new(seconds: date.end_of_day.to_i) }
    when "<"
      { before: Google::Protobuf::Timestamp.new(seconds: date.beginning_of_day.to_i) }
    end

    Proto::TrustMetadataApi::V0::TimestampRange.new(**T.must(range_args))
  rescue ArgumentError
    nil
  end

  # Splits an optional comparison operator prefix from a date string.
  # Returns [operator, date] where operator defaults to "=" when absent.
  sig { params(date_string: String).returns([String, String]) }
  def self.parse_date_operator(date_string)
    if (match = date_string.match(/\A(>=|<=|>|<|=)(.+)\z/))
      [T.must(match[1]), T.must(match[2])]
    else
      ["=", date_string]
    end
  end

  # Fetches a single attestation by ID for a repository using the ListAttestations endpoint.
  # Used as a replacement for get_attestation_summary_by_repository and get_attestation_by_repository.
  # Callers specify which enrichments they need (e.g. CERTIFICATE_SUMMARY, SUBJECT_SUMMARY, BUNDLE).
  sig do
    params(
      repo: Repository,
      attestation_id: Integer,
      enrichments: T::Array[Integer],
      initiator: T.nilable(String)
    ).returns(T.untyped)
  end
  def self.get_attestation_by_id_and_repository(repo, attestation_id:, enrichments:, initiator: nil)
    filters = Proto::TrustMetadataApi::V0::AttestationFilters.new(
      repository_id: repo.id,
      attestation_ids: [attestation_id],
      initiator: initiator
    )

    request = Proto::TrustMetadataApi::V0::ListAttestationsRequest.new(
      owner_id: repo.owner_id,
      filters: filters,
      enrichments: enrichments
    )

    list_attestations(request)
  end

  # Fetches all subjects for a given attestation using the ListSubjects endpoint.
  # Paginates through all pages to collect every subject.
  # Returns a TwirpResponse whose value is a ListSubjectsResponse wrapping all collected subjects.
  # The server enforces a max of 1024 subjects per attestation; at 100 per page, 11 pages covers that.
  MAX_SUBJECTS_PAGES = 11

  sig do
    params(
      repo: Repository,
      attestation_id: Integer
    ).returns(T.untyped)
  end
  def self.list_subjects_by_attestation(repo, attestation_id:)
    filters = Proto::TrustMetadataApi::V0::SubjectFilters.new(
      attestation_ids: [attestation_id]
    )

    all_subjects = T.let([], T::Array[T.untyped])
    cursor = T.let(nil, T.nilable(String))
    pages_fetched = 0

    loop do
      request = Proto::TrustMetadataApi::V0::ListSubjectsRequest.new(
        owner_id: repo.owner_id,
        filters: filters,
        per_page: 100
      )
      request.after = cursor if cursor

      resp = TwirpHelper.rescue_from_twirp_errors(SERVICE_NAME, app: FAILBOT_APP_NAME) do
        tma_client.list_subjects(request)
      end

      return resp unless resp.call_succeeded?

      all_subjects.concat(resp.value.subjects.to_a)
      pages_fetched += 1

      page_info = resp.value.page_info
      break unless page_info&.has_next_page && pages_fetched < MAX_SUBJECTS_PAGES
      break if page_info.end_cursor.blank?

      cursor = page_info.end_cursor
    end

    # Return a successful response wrapping the accumulated subjects.
    final_response = Proto::TrustMetadataApi::V0::ListSubjectsResponse.new(
      subjects: all_subjects
    )
    TwirpResponse.new(value: final_response, status: 200, call_succeeded: true)
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
