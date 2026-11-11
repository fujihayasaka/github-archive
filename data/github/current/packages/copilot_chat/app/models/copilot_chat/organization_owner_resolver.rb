# typed: true
# frozen_string_literal: true

module CopilotChat
  # Resolves the organization ID that owns a given resource.
  #
  # This class determines which organization (if any) owns or is associated with a resource
  # like a Repository, Issue, Pull Request, etc. It returns the organization ID if the
  # resource is owned by an organization, or nil if it's owned by a user or not found.
  #
  # The resolver handles multiple resource lookup strategies:
  # - Direct resource lookup by type and ID
  # - Repository lookup by NWO (name with owner)
  # - Repository lookup by repository_id
  # - Issue/PR lookup by number and repository NWO
  #
  # @return [Integer, nil] The organization ID if owned by an org, or nil otherwise
  class OrganizationOwnerResolver
    # Allowlist of resource types that can be resolved to organizations
    ALLOWED_RESOURCE_TYPES = %w[
      Repository
      Issue
      IssueComment
      PullRequest
      Organization
      Discussion
      Release
      Ci
    ].freeze

    # Resource types that use number-based lookups
    NUMBER_LOOKUP_TYPES = %w[IssueNumber PullRequestNumber].freeze

    ALL_VALID_TYPES = (ALLOWED_RESOURCE_TYPES + NUMBER_LOOKUP_TYPES).freeze

    # Resolve organization IDs for multiple resources in batch.
    # Returns an array of organization IDs (compacted, nils removed) or a Twirp::Error on first failure.
    #
    # @param resource_infos [Array<Hash>] Array of hashes with keys:
    #   - resource_type: String
    #   - resource_id: Integer
    #   - organization_id: Integer
    #   - repository_id: Integer
    #   - repository_nwo: String
    # @return [Array<Integer>, Twirp::Error] Array of organization IDs or error
    sig do
      params(
        resource_infos: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(T.any(T::Array[Integer], Twirp::Error))
    end
    def self.resolve_organization_ids(resource_infos)
      new.resolve_batch(resource_infos)
    end

    sig do
      params(
        resource_infos: T::Array[T::Hash[Symbol, T.untyped]]
      ).returns(T.any(T::Array[Integer], Twirp::Error))
    end
    def resolve_batch(resource_infos)
      return [] if resource_infos.empty?

      valid_resource_infos = resource_infos.select do |info|
        resource_type = info[:resource_type]
        if ALL_VALID_TYPES.include?(resource_type)
          true
        else
          GitHub.logger.info("Unknown resource_type encountered",
            "gh.copilotapi.access_control.resource_type": resource_type
          )
          false
        end
      end

      # Step 1: Collect all repository IDs from all sources
      all_repo_ids = collect_all_repository_ids(valid_resource_infos)

      # Step 2: Fetch org IDs from the organizations that were explicitly referenced
      org_ids_from_param = fetch_org_ids_from_param(valid_resource_infos)

      # Step 3: Resolve all repository IDs to organization IDs in a single query
      org_ids_from_repos = org_ids_from_repository_ids(all_repo_ids)

      # Combine all org IDs and remove duplicates
      (org_ids_from_repos + org_ids_from_param).uniq
    end

    private

    # Collect all repository IDs from all resource types and lookup methods
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def collect_all_repository_ids(resource_infos)
      repo_ids = []

      # Direct repository IDs from resource_id when type is Repository
      repo_ids.concat(extract_resource_ids(resource_infos, "Repository"))

      # Repository IDs from repository_id parameter
      repo_ids.concat(resource_infos.filter_map { |info| info[:repository_id] if info[:repository_id]&.positive? })

      # Repository IDs from NWO lookups
      repo_ids.concat(fetch_repo_ids_by_nwo(resource_infos))

      # Repository IDs from Issue lookups
      repo_ids.concat(fetch_repo_ids_from_issues(resource_infos))

      # Repository IDs from PullRequest lookups
      repo_ids.concat(fetch_repo_ids_from_pull_requests(resource_infos))

      # Repository IDs from IssueComment lookups
      repo_ids.concat(fetch_repo_ids_from_issue_comments(resource_infos))

      # Repository IDs from Issue/PR number lookups
      repo_ids.concat(fetch_repo_ids_from_issue_number_lookups(resource_infos))
      repo_ids.concat(fetch_repo_ids_from_pr_number_lookups(resource_infos))

      repo_ids.compact.uniq
    end

    # Fetch repository IDs by NWO
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_by_nwo(resource_infos)
      nwos = resource_infos.filter_map { |info| info[:repository_nwo] if info[:repository_nwo].present? }.uniq
      return [] if nwos.empty?

      # Handle repository redirects for renamed repositories
      if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
        nwos.map { |nwo| Repository.with_name_with_owner(nwo, search_redirects: true) }.compact.map(&:id)
      else
        Repository.with_names_with_owners(nwos).pluck(:id)
      end
    end

    # Fetch repository IDs from Issue resources
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_from_issues(resource_infos)
      issue_ids = extract_resource_ids(resource_infos, "Issue")
      return [] if issue_ids.empty?

      Issue.where(id: issue_ids).pluck(:repository_id).compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Fetch repository IDs from PullRequest resources
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_from_pull_requests(resource_infos)
      pr_ids = extract_resource_ids(resource_infos, "PullRequest")
      return [] if pr_ids.empty?

      PullRequest.where(id: pr_ids).pluck(:repository_id).compact
    end

    # Fetch repository IDs from IssueComment resources
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_from_issue_comments(resource_infos)
      comment_ids = extract_resource_ids(resource_infos, "IssueComment")
      return [] if comment_ids.empty?

      IssueComment.where(id: comment_ids).joins(:issue).pluck("issues.repository_id").compact # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    end

    # Fetch repository IDs from IssueNumber lookups
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_from_issue_number_lookups(resource_infos)
      fetch_repo_ids_from_number_lookups(resource_infos, "IssueNumber", pull_request: false)
    end

    # Fetch repository IDs from PullRequestNumber lookups
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]]).returns(T::Array[Integer]) }
    def fetch_repo_ids_from_pr_number_lookups(resource_infos)
      fetch_repo_ids_from_number_lookups(resource_infos, "PullRequestNumber", pull_request: true)
    end

    # Generic helper for fetching repo IDs from issue/PR number lookups
    sig do
      params(
        resource_infos: T::Array[T::Hash[Symbol, T.untyped]],
        lookup_type: String,
        pull_request: T::Boolean
      ).returns(T::Array[Integer])
    end
    def fetch_repo_ids_from_number_lookups(resource_infos, lookup_type, pull_request:)
      lookups = resource_infos.filter_map do |info|
        if info[:resource_type] == lookup_type && info[:resource_id] && info[:repository_nwo].present?
          { number: info[:resource_id], nwo: info[:repository_nwo] }
        end
      end
      return [] if lookups.empty?

      # Batch fetch all repos first, handling redirects for renamed repositories
      nwos = lookups.map { |l| l[:nwo] }.uniq
      if FeatureFlag.vexi.enabled?(:copilot_chat_search_renamed_repos, default: false)
        # When searching redirects, we need to map the original NWO to the found repository
        # because the repository may have been renamed and we need to look it up by the old name
        repos_by_nwo = nwos.each_with_object({}) do |nwo, hash|
          repo = Repository.with_name_with_owner(nwo, search_redirects: true)
          hash[nwo.downcase] = repo if repo
        end
      else
        repos_by_nwo = Repository.with_names_with_owners(nwos)
          .index_by { |r| r.name_with_display_owner.downcase }
      end

      # Build pairs for batch issue lookup
      repo_number_pairs = lookups.filter_map do |lookup|
        repo = repos_by_nwo[lookup[:nwo].downcase]
        [repo.id, lookup[:number]] if repo
      end
      return [] if repo_number_pairs.empty?

      repo_ids = repo_number_pairs.map(&:first).uniq
      numbers = repo_number_pairs.map(&:last).uniq

      # Batch fetch all matching issues/PRs
      Issue.where(repository_id: repo_ids, number: numbers, pull_request: pull_request)
        .pluck(:repository_id) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        .compact
    end

    # Common query pattern: Given repository IDs, return organization IDs that own them
    sig { params(repository_ids: T::Array[Integer]).returns(T::Array[Integer]) }
    def org_ids_from_repository_ids(repository_ids)
      return [] if repository_ids.empty?

      owner_ids = Repository.where(id: repository_ids).pluck(:owner_id).uniq
      Organization.where(id: owner_ids).pluck(:id)
    end

    # Helper to extract resource IDs for a given resource type
    sig { params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]], type: String).returns(T::Array[Integer]) }
    def extract_resource_ids(resource_infos, type)
      ids = resource_infos.filter_map do |info|
        id = info[:resource_id]
        id if info[:resource_type] == type && id && id > 0
      end
      ids.uniq
    end

    sig do
      params(resource_infos: T::Array[T::Hash[Symbol, T.untyped]])
        .returns(T::Array[Integer])
    end
    def fetch_org_ids_from_param(resource_infos)
      org_ids = resource_infos.filter_map { |info| info[:organization_id] if info[:organization_id]&.positive? }.uniq
      return [] if org_ids.empty?

      # Verify these are actual organizations
      Organization.where(id: org_ids).pluck(:id)
    end
  end
end
