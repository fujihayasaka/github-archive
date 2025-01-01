# typed: true
# frozen_string_literal: true

class TopRepositories
  include GitHub::SimplePagination

  def self.for(viewer:, since: 4.months.ago, cap_filter:)
    new(viewer, since: since, cap_filter: cap_filter)
  end

  def initialize(viewer, since:, cap_filter:)
    @viewer = viewer
    @cap_filter = cap_filter
    @limit = nil
    @offset = nil

    since ||= 4.months.ago
    @since = since.clamp(1.year.ago, Time.zone.now)
  end

  def limit(n)
    @limit = n
    self
  end

  def offset(n)
    @offset = n
    self
  end

  def to_a
    all_repos = (ranked_repositories + unranked_repositories).uniq(&:id)
    all_repos = all_repos.drop(@offset) if @offset
    all_repos = all_repos.take(@limit) if @limit

    all_repos
  end

  private

  attr_reader :viewer, :cap_filter

  def ranked_repositories
    return [] if viewer.large_bot_account?

    ranked_repos = viewer.repositories_contributed_to(
      viewer: viewer,
      limit: nil,
      exclude_owned: false,
      since: @since,
    )

    authorized_organization_ids = cap_filter.authorized_resource_ids(ranked_repos)

    ranked_repos.filter { |repo| authorized_organization_ids.include?(repo.id) && repo.active? }.compact
  end

  def unranked_repositories
    scope = repository_finder.filter(
      affiliations: [:owned, :direct],
      owner_affiliations: [:owned, :direct],
      order_by: { field: :pushed_at, direction: :desc },
    )
    authorized_ids = cap_filter.authorized_resource_ids(scope)
    scope.includes(:owner).where(id: authorized_ids)
  end

  def repository_finder
    Repositories::Public.finder_for(
      owner: viewer,
      viewer: viewer,
      permission: permission,
      repo_type: "default",
      unauthorized_viewer_organization_ids: []
    )
  end

  def permission
    Platform::Authorization::Permission.new(viewer: viewer, origin: Platform::ORIGIN_INTERNAL)
  end
end
