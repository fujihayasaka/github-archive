# typed: true
# frozen_string_literal: true

# This module adds methods to resolve issue mentions
# It can resolve nwo_mentions and URL references:
# - #13
# - repo#13
# - owner/repo#13
# - https://github.com/github/github/issues/1
module GitHub
  module IssueReferenceResolution
    extend T::Helpers

    requires_ancestor { Object }

    include GitHub::IssueReferenceParser

    # Use this method to efficiently resolve a bunch of issue references using as little SQL queries as possible
    # Note: the order of the returned issues IS NOT GUARANTEED
    #
    # @param references [Array<String>] - a string array representing issues (owner/repo#issue_number or URL)
    # @param reference_repo [Repository] - a repository to be used as a basis of resolution
    def batch_resolve_issue_references(references, reference_repo)
      if !references.is_a?(Array)
        raise ArgumentError, "batch_resolve_issue_references accepts only array of strings as an input"
      end

      parsed_refs = parse_references(references).compact
      return [] if parsed_refs.empty?

      groups = group_refs(parsed_refs)
      repo_nwos = groups.keys.select { |key| key.present? }

      nwos_to_repo_id = resolve_repo_ids(repo_nwos)

      # edge case for references without nwo (using current repo)
      nwos_to_repo_id[nil] = reference_repo.id

      predicate = groups.reduce(nil) do |predicate, group|
        nwo = group[0]
        issue_numbers = group[1]
        repo_id = nwos_to_repo_id[nwo]

        if predicate.nil?
          Issue.where(repository_id: repo_id, number: issue_numbers).arel.constraints.first
        else
          predicate.or(
                    Issue.where(repository_id: repo_id, number: issue_numbers).arel.constraints.first
                  )
        end
      end

      Issue.where(predicate)
    end

    # @param reference [String, URL] - a string representing an issue (owner/repo#issue_number or URL)
    # @param reference_repo [Repository] - a repository to be used as a basis of resolution
    def resolve_issue_reference(reference, reference_repo)
      ref = parse_reference(reference)
      return unless ref
      get_issue_from_nwo_mention(ref, reference_repo)
    end

    # @param reference [String, URL] - a string representing an issue (owner/repo#issue_number or URL)
    # @param reference_repo [Repository] - a repository to be used as a basis of resolution
    # @param viewer [User] - an optional user to use for viewing permission checks
    def resolve_issue_reference_with_permissions(reference, reference_repo, viewer)
      issue = resolve_issue_reference(reference, reference_repo)
      issue if issue.present? && viewer.present? && issue.readable_by?(viewer)
    end

    # Find repository based on nwo
    # @param nwo [String, Repository] - a string representing name and owner of the repo OR a repository entity
    # @param reference_repo [Repository] - a repository, which will be used as a base of resolution
    def find_repo(nwo, reference_repo)
      case nwo
      when Repository
        nwo
      when /\A\s*\z/, nil
        reference_repo
      when Repository::NAME_WITH_OWNER_PATTERN
        # Pick out the special case where a repo is referenced by numeric owner_id and repo_id e.g. "123/456".
        owner_id, repo_id = nwo =~ /\A\d+\/\d+\z/ ? nwo.split("/") : [nil, nil]
        resolve_id_based_url_references = owner_id && repo_id

        if repo = Repository.with_name_with_owner(nwo)
          repo
        elsif resolve_id_based_url_references && repo_from_ids = Repository.find_by(owner_id: owner_id, id: repo_id)
          repo_from_ids
        elsif renamed = RepositoryRedirect.find_redirected_repository(nwo)
          renamed
        end
      else
        if reference_repo
          if user = User.find_by_login(nwo)
            reference_repo.network_repositories.find_by_owner_id(user.id)
          elsif renamed = RepositoryRedirect.find_networked_by_old_owner(nwo, reference_repo)
            renamed
          end
        end
      end
    end

    private

    # Returns an issue referenced by nwo#number mention
    #
    # @param reference [ParsedReference] - an object representing an issue nwo mention
    # @param reference_repo [Repository] - a repository to be used as a basis of resolution
    def get_issue_from_nwo_mention(ref, reference_repo)
      repository = find_repo(ref[:nwo], reference_repo)
      return unless repository
      issuish = T.let(nil, T.nilable(Issue))

      # first try to find the issue/PR in the current or explicitly
      # referenced repository
      issuish = get_referenced_issue(repository, ref[:number])

      # if the issue wasn't found, try searching up the parent chain but only when
      # no explicit repository reference was given (i.e., "foo/bar#33" won't
      # search in other repositories).
      if issuish.nil? && repository.blank?
        while repository = repository.parent do
          issuish = get_referenced_issue(repository, ref[:number])
          break if issuish
        end
      end
      issuish
    end

    sig { params(repository: Repository, number: T.untyped).returns(T.nilable(Issue)) }
    def get_referenced_issue(repository, number)
      if (issue = repository.issues.find_by(number: number)) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        # PRs can't be disabled, so return the Issue
        # for a PR even if Issues are disabled
        if repository.has_issues || issue.pull_request?
          issue
        end
      end
    end

    def resolve_repo_ids(repo_nwos)
      Repository.with_names_with_owners(repo_nwos)
          .index_by { |repo| repo.name_with_display_owner.downcase }
          .map { |repo| [repo[0], repo[1].id] }
          .to_h
    end

    def group_refs(parsed_refs)
      groups = parsed_refs
        .group_by { |r| r[:nwo] }
        .map do |g|
          [
            g[0],
            get_numbers(g[1])
          ]
        end

      groups.to_h
    end

    def get_numbers(parsed_refs)
      parsed_refs.map { |val| val[:number] }
    end

    extend self
  end
end
