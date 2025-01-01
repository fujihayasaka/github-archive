module Queries
  class RepositoryOwnerDependenciesQuery
    attr_reader :cache_key

    # github_owner_id - Integer User or Organization database ID from dotcom whose repositories should be checked
    #                   to see what packages they depend on
    # public_only - Boolean indicating whether only the specified `github_owner_id`'s public repositories should be
    #               checked for dependencies or not
    # direct_only - Boolean indicating whether only direct dependencies for the specified `github_owner_id` should be
    #               included
    # sort_by - optional Symbol indicating how to sort the results; choose from :most_used, :least_used,
    #           :package_manager, :package_name, :recently_published, :least_recently_published
    # package_managers - optional Array containing either Types::PackageManager or String like "rubygems" or "maven",
    #                    to filter dependencies to only those having one of the specified ecosystems
    # github_repository_ids - optional Array of Integer database IDs of repositories to check for dependencies
    def initialize(github_owner_id, public_only: false, direct_only: false, sort_by: nil, package_managers: [], github_repository_ids: [])
      @dependencies = AbstractRepositoryDependency
        .repository_owned_by(github_owner_id)
        .join_packages
        .group(Package.arel_table[:repository_id])

      @dependencies = @dependencies.for_github_repository(github_repository_ids) if github_repository_ids.any?
      @dependencies = @dependencies.with_public_repo if public_only
      @dependencies = @dependencies.direct_only if direct_only
      @dependencies = @dependencies.with_package_manager(package_managers) if package_managers.any?

      case sort_by
      when :package_manager
        @dependencies = @dependencies.sort_by_package_manager
      when :package_name
        @dependencies = @dependencies.sort_by_package_name
      when :recently_published
        @dependencies = @dependencies.sort_by_recently_published
      when :least_recently_published
        @dependencies = @dependencies.sort_by_least_recently_published
      when :most_used
        @dependencies = @dependencies.order(Arel.sql("COUNT(*) DESC"))
      when :least_used
        @dependencies = @dependencies.order(Arel.sql("COUNT(*) ASC"))
      end

      @cache_key = compute_cache_key(owner_id: github_owner_id, sort_by:, package_managers:, public_only:, direct_only:, repository_ids: github_repository_ids)
    end

    def dependencies
      @dependencies.count.keys.compact
    end

    private

    MAX_REPOSITORY_IDS = 100

    def compute_cache_key(owner_id:, sort_by:, package_managers:, public_only:, direct_only:, repository_ids:)
      is_public = public_only ? 1 : 0
      sort = (sort_by || "none").downcase
      pkg_mgr = if package_managers.present?
                  package_managers.to_a.compact.uniq.sort_by { |p| p.to_i }.join("-").downcase
                else
                  "none"
                end

      normalized_repository_ids = repository_ids.compact.uniq.take(MAX_REPOSITORY_IDS)
      any_repo_ids = normalized_repository_ids.any?

      parts = [
        "repo-owner-#{owner_id}-deps",
        "public:#{is_public}",
        "sort:#{sort}",
        "pkg-mgr:#{pkg_mgr}",
        direct_only ? "direct-only" : nil,
        any_repo_ids ? "limited-repos" : nil,
      ]
      parts.compact.join("-")
    end
  end
end
