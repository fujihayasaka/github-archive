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

  class ErrNoRepoAccess < StandardError
    attr_reader :org_id

    def initialize(org_id)
      @org_id = org_id
      super("No access to repository when fetching repository and attestation IDs for organization #{org_id}")
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
    if repos_and_attestation_ids_hash.length != 1
      raise ErrNoArtifactsFound.new(digest, org.id)
    end
    if repos_and_attestation_ids_hash[digest].nil?
      raise ErrNoArtifactsFound.new(digest, org.id)
    end

    T.must(repos_and_attestation_ids_hash[digest])
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
        next if entry.github_repo_name.nil?

        found = Repository.find_by(name: entry.github_repo_name, owner_id: org.id)
        if found.nil?
          raise ErrNoRepoAccess.new(org.id)
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
