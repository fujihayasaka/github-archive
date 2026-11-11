# typed: true
# frozen_string_literal: true

class TopRepositories
  include GitHub::SimplePagination

  def self.paginated_for(viewer:, cap_filter:, page: 1, per_page:, initial_per_page:)
    new(viewer, since: 1.year.ago, cap_filter: cap_filter)
      .simple_paginate(per_page: per_page, page: page, initial_per_page: initial_per_page)
  end

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
    ranked = ranked_repositories
    needed = (@offset || 0) + (@limit || 0)

    all_repos = if needed > 0 && ranked.size >= needed
      ranked
    else
      (ranked + unranked_repositories).uniq(&:id)
    end

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
    affiliations = unranked_affiliations
    scope = repository_finder.filter(
      affiliations: affiliations,
      owner_affiliations: affiliations,
      order_by: { field: :pushed_at, direction: :desc },
    ).includes(:owner)
    cap_filter.authorized_resources(scope)
  end

  def unranked_affiliations
    if FeatureFlag.vexi.enabled?(:dashboard_top_repos_include_indirect, viewer, default: false)
      [:owned, :direct, :indirect]
    else
      [:owned, :direct]
    end
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
