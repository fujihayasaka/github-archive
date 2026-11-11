# typed: true
# frozen_string_literal: true

class ArtifactMetadataManager
  class ErrNoArtifactsFound < StandardError
    attr_reader :digest, :org_id

    def initialize(digest, org_id)
      @digest = digest
      @org_id = org_id
      super("No artifacts found for organization #{org_id} and digest #{digest}")
    end
  end

  class ErrMissingDigest < StandardError
    attr_reader :org_id

    def initialize(org_id)
      @org_id = org_id
      super("Missing digest when fetching repository and attestation IDs for organization #{org_id}")
    end
  end

  class ErrRepositoryNotFound < StandardError
    sig { returns(Integer) }
    attr_reader :org_id

    sig { returns(String) }
    attr_reader :repo_name

    sig { params(org_id: Integer, repo_name: String).void }
    def initialize(org_id, repo_name)
      @org_id = org_id
      @repo_name = repo_name
      super("Repository not found when looking up by name for organization #{org_id} and repository #{repo_name}")
    end
  end

  class ErrUnexpectedBulkResponse < StandardError
    attr_reader :org_id, :digest

    sig { params(org_id: Integer, digest: String, expected_entries: Integer, actual_entries: Integer).void }
    def initialize(org_id, digest, expected_entries, actual_entries)
      @org_id = org_id
      @digest = digest
      super("Unexpected bulk response structure for organization #{org_id} and digest #{digest}: expected #{expected_entries} entry hash, got #{actual_entries}")
    end
  end

  class ErrTrustMetadata < StandardError; end

  # max number of pages to fetch from TMA when looking for attestations
  # to avoid infinite loops
  MAX_PAGES = 50
  DIGEST_BATCH_SIZE = 100

  class DigestGitHubRepoTuple < T::Struct
    const :digest, String
    const :github_repo_name, T.nilable(String)
  end

  # Fetch repository ID and attestation ID based on whether a provenance attestation
  # associated with the given org and digest exists
  # Returns a hash mapping digest to an array of attestation and repository ID pairs
  sig { params(org: Organization, digest: String, github_repo_name: T.nilable(String)).returns(T::Array[{ attestation_id: Integer, repository_id: Integer }]) }
  def self.get_repository_and_attestation_ids(org, digest, github_repo_name)
    tup = DigestGitHubRepoTuple.new(digest: digest, github_repo_name: github_repo_name)
    digests_and_repos = [tup]
    repos_and_attestation_ids_hash = self.get_repository_and_attestation_ids_in_bulk(org, digests_and_repos)

    entry = repos_and_attestation_ids_hash[digest]
    hash_size = repos_and_attestation_ids_hash.length

    # If no entry was found for the single requested digest, it means there are no provenance attestations associated
    if entry.nil?
      raise ErrNoArtifactsFound.new(digest, org.id)
    end

    # The bulk call should return exactly 1 entry for the single digest we passed in;
    # any other count indicates an unexpected response structure.
    if hash_size != 1
      raise ErrUnexpectedBulkResponse.new(org.id, digest, 1, hash_size)
    end

    T.must(entry)
  end

  # Fetch repository IDs and attestation IDs based on whether provenance attestations
  # associated with the given org and digest exist or if the github-repository
  # request body parameter is provided
  sig { params(org: Organization, digests_and_repos: T::Array[DigestGitHubRepoTuple]).returns(T::Hash[String, T::Array[{ attestation_id: Integer, repository_id: Integer }]]) }
  def self.get_repository_and_attestation_ids_in_bulk(org, digests_and_repos)
    digests = digests_and_repos.map { |entry| entry.digest }.uniq
    # Default to checking for provenance attestations using the digest first
    # If any are found, return the associated repository IDs and attestation IDs
    raise ErrMissingDigest.new(org.id) if digests.empty?

    # first attempt to fetch attestation and repository IDs from TMA
    attestation_identifiers_by_digest_from_tma = {}
    begin
      attestation_identifiers_by_digest_from_tma = fetch_attestation_identifiers_from_tma!(org, digests)
    rescue ErrTrustMetadata => e
      GitHub.logger.error("call to fetch attestations from TMA with org #{org.id} and digests #{digests.join(', ')} failed", "gh.org.id" => org.id, "gh.repo.attestation.subject_digests" => digests)
      # If there was an error fetching from TMA, the only way to recover is if a github repo name
      # was provided for every digest. If not, raise the error.
      digests_and_repos.each do |entry|
        if entry.github_repo_name.nil?
          raise ErrTrustMetadata
        end
      end
    end

    # Combine results from TMA with any provided digests that did not have attestations
    all_attestation_identifiers_by_digest = digests_and_repos.each_with_object({}) do |entry, h|
      digest = entry.digest
      # If the digest had attestations from TMA, add them to the result set
      if attestation_identifiers_by_digest_from_tma.key?(digest)
        entries = T.must(attestation_identifiers_by_digest_from_tma[digest])
        h[digest] = entries
      else
        # If no attestations were found from TMA, we can only proceed if a github repo name was provided
        next if entry.github_repo_name.blank?

        found = Repository.find_by(name: entry.github_repo_name, owner_id: org.id)
        if found.nil?
          raise ErrRepositoryNotFound.new(org.id, T.must(entry.github_repo_name))
        end

        # No attestations found, but github repo name was provided, so return repository ID with nil attestation ID
        (h[digest] ||= []) << {
          attestation_id: nil,
          repository_id: found.id
        }
      end
    end

    all_attestation_identifiers_by_digest
  end

  sig { params(org: Organization, digests: T::Array[String], metrics: SetClusterRecordMetricsBase).returns(T::Hash[String, T::Array[{ attestation_id: Integer, repository_id: Integer }]]) }
  def self.fetch_validated_attestation_identifiers!(org, digests, metrics)
    identifiers = fetch_attestation_identifiers_from_tma!(org, digests)

    # Ensure that all repository IDs we intend to use actually resolve to repositories owned by this org.
    # If there is any mismatch, fail early so that missing or cross-org repositories cannot bypass authz
    # or data-integrity checks. This can only happen when repository IDs fetched from the TMA have been
    # transferred to another organization since the attestations were created. The TMA currently does not update
    # existing entries to account for repository transfer or deletion.
    # This check could be removed in the future If TMA is updated to handle this edge case
    all_repo_ids = identifiers.values.flatten.map { |id| id[:repository_id] }

    # Bulk lookup which repos actually exist in this org
    valid_repo_ids = Repository.where(id: all_repo_ids, owner_id: org.id).pluck(:id).to_set

    # Filter the TMA results to only valid repos, dropping digests whose identifiers were all removed
    filtered_identifiers = identifiers.each_with_object({}) do |(digest, digest_identifiers), filtered|
      valid_identifiers = digest_identifiers.select { |id| valid_repo_ids.include?(id[:repository_id]) }
      filtered[digest] = valid_identifiers if valid_identifiers.any?
    end

    # Then track how many entries were filtered out (for your metric)
    original_identifier_count = identifiers.values.sum(&:size)
    filtered_identifier_count = filtered_identifiers.values.sum(&:size)
    invalidated_count = original_identifier_count - filtered_identifier_count
    if invalidated_count > 0
      invalidated_repo_ids = all_repo_ids.uniq - valid_repo_ids.to_a
      GitHub.logger.warn(
        "Mismatch between requested repositories and repositories belonging to org #{org.id}. " \
        "Requested: #{all_repo_ids}, Found: #{valid_repo_ids.to_a}, Invalidated: #{invalidated_repo_ids}, " \
        "Invalidated entry count: #{invalidated_count}",
      )
      metrics.publish_distribution_metric("tma_repository_org_mismatch", invalidated_count)
    end

    filtered_identifiers
  end

  # Fetch attestation identifiers from Trust Metadata API for a given organization and list of digests
  # Returns a hash mapping digest to an array of attestation and repository ID pairs
  sig { params(org: Organization, digests: T::Array[String]).returns(T::Hash[String, T::Array[{ attestation_id: Integer, repository_id: Integer }]]) }
  def self.fetch_attestation_identifiers_from_tma!(org, digests)
    attestation_identifiers = {}
    digests.each_slice(DIGEST_BATCH_SIZE) do |digest_batch|
      end_cursor = T.let(nil, T.untyped)
      pages = 0
      loop do
        pages += 1
        if pages > MAX_PAGES
          GitHub.logger.warn(
            "TMA pagination exceeded maximum of #{MAX_PAGES} pages for organization #{org.id} with digests #{digest_batch.join(', ')}",
            "gh.org.id" => org.id,
            "gh.repo.attestation.subject_digests" => digest_batch,
          )
          break
        end

        response = TrustMetadata.get_attestation_identifiers_by_subject_digest(org, digest_batch, predicate_type: "provenance", after: end_cursor)
        if !response.call_succeeded?
          if response.status == 404
            break
          end

          raise ErrTrustMetadata, "TrustMetadata API call failed for org #{org.id} with digests #{digest_batch.join(', ')}"
        end

        resp_body = response.value
        break if resp_body.nil? || resp_body.attestation_identifiers.empty?

        resp_body.attestation_identifiers.each do |ai|
          (attestation_identifiers[ai.subject_digest] ||= []) << {
            attestation_id: ai.attestation_id,
            repository_id: ai.repository_id,
          }
        end

        break unless resp_body&.page_info&.hasNextPage
        end_cursor = resp_body.page_info.endCursor
      end
    end

    attestation_identifiers
  end
end
