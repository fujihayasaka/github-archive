# typed: strict
# frozen_string_literal: true

module CopilotSpaces
  module ResourceFiltering
    extend ActiveSupport::Concern

    # Load repositories by ID, authorize via CAP, and filter to those
    # readable by the viewer. Returns the authorized Repository objects.
    sig { params(repository_ids: T::Array[Integer], cap_filter: ConditionalAccess::Filter, viewer: User).returns(T::Array[Repository]) }
    def authorized_repositories(repository_ids, cap_filter, viewer)
      repos = Repositories::Public.load_repositories(repository_ids).includes(:owner)

      # We need to check readability and cap filter. Docs for CAP: https://thehub.github.com/epd/engineering/products-and-services/dotcom/cap/cookbook/
      cap_filter.authorized(repos).results.map(&:resource).filter do |repo|
        repo.readable_by?(viewer)
      end
    end

    # Filter a list of resources to only those visible to the given user.
    # Batch-loads all repository data in a single query and runs CAP
    # authorization once, avoiding N+1 queries when filtering many resources.
    sig { params(resources: T::Array[CopilotSpaceResource], cap_filter: ConditionalAccess::Filter, user: User).returns(T::Array[CopilotSpaceResource]) }
    def filter_visible_resources(resources, cap_filter, user)
      filter_visible_resources_with_repos(resources, cap_filter, user)[:visible_resources]
    end

    # Same as filter_visible_resources but also returns the authorized repos
    # indexed by ID, for callers that need the repo objects (e.g., to build
    # serialized payloads or compute content sizes).
    sig do
      params(resources: T::Array[CopilotSpaceResource], cap_filter: ConditionalAccess::Filter, user: User)
        .returns({ visible_resources: T::Array[CopilotSpaceResource], authorized_repos_by_id: T::Hash[Integer, Repository] })
    end
    def filter_visible_resources_with_repos(resources, cap_filter, user)
      empty_result = { visible_resources: T.let([], T::Array[CopilotSpaceResource]), authorized_repos_by_id: T.let({}, T::Hash[Integer, Repository]) }
      return empty_result if resources.empty?

      restricted, unrestricted = resources.partition do |r|
        CopilotSpace::REPO_BACKED_RESOURCE_TYPES.include?(r.resource_type)
      end

      empty_repos = T.let({}, T::Hash[Integer, Repository])

      if restricted.empty?
        return { visible_resources: unrestricted, authorized_repos_by_id: empty_repos }
      end

      repo_ids = restricted.filter_map(&:repository_id).uniq
      if repo_ids.empty?
        return { visible_resources: unrestricted, authorized_repos_by_id: empty_repos }
      end

      authorized_repos = authorized_repositories(repo_ids, cap_filter, user)
      authorized_repos_by_id = authorized_repos.index_by(&:id)

      visible_restricted = restricted.select { |r| authorized_repos_by_id.key?(r.repository_id) }

      { visible_resources: visible_restricted + unrestricted, authorized_repos_by_id: }
    end

    # Check if a single resource is visible to the given user.
    # Delegates to filter_visible_resources for consistency.
    sig { params(resource: CopilotSpaceResource, cap_filter: ConditionalAccess::Filter, user: User).returns(T::Boolean) }
    def resource_visible?(resource, cap_filter, user)
      filter_visible_resources([resource], cap_filter, user).include?(resource)
    end
  end
end
