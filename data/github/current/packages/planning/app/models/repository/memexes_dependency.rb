# typed: true
# frozen_string_literal: true

require "digest"

module Repository::MemexesDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { Repository }

  include MemexProject::SharedMemexProjectsDependency
  include Configurable::DisableRepositoryMemexProjects

  class CannotEnableProjectsError < StandardError; end

  included do
    T.bind(self, T.class_of(Repository))
    # rubocop:todo Rails/InverseOf
    has_many :memex_project_links, -> { where(source_type: "Repository") }, foreign_key: :source_id, dependent: :destroy
    # rubocop:enable Rails/InverseOf
    has_many :memex_projects, through: :memex_project_links, source: :memex_project
  end

  # Public: returns a scope of memex projects linked to this repository
  #
  # Returns a scope
  def memex_projects_scope_for(viewer, min_permission_level = "read", filter_ids: [])
    async_memex_projects_scope_for(viewer, filter_ids: filter_ids).sync
  end

  def async_memex_projects_scope_for(viewer, min_permission_level = "read", numbers: nil, filter_ids: [])
    return Promise.resolve(MemexProject.none) unless memex_project_links.any?

    self.async_owner.then do |_owner|
      async_accessible_memexes_scope(
        memex_projects,
        viewer,
        min_permission_level,
        filter_ids: filter_ids
      ).then do |scope|
        scope.where(deleted_at: nil)
          .order("id")
      end
    end
  end

  # Public: does the given user have access to memex projects
  #
  # Returns a boolean
  def memex_projects_enabled?
    GitHub.projects_new_enabled? && is_memex_projects_enabled?
  end

  def async_memex_projects_enabled?
    Promise.resolve(memex_projects_enabled?)
  end

  # Public: Can memex projects be enabled for this repository?
  #
  # Returns a Boolean.
  def can_enable_memex_projects?
    async_can_enable_memex_projects?.sync
  end

  # Public: Can memex_projects be enabled for this repository?
  #
  # Returns a Promise<Boolean>.
  def async_can_enable_memex_projects?
    async_owner.then do |owner|
      next true unless T.must(owner).organization?
      GitHub.projects_new_enabled? && T.cast(owner, Organization).organization_projects_enabled?
    end
  end

  def enable_repository_memex_projects(**arguments)
    ensure_memex_projects_can_be_enabled!
    super
  end

  def has_repository_memex_projects=(new_value)
    set_has_repository_memex_projects(new_value)
  end

  def set_has_repository_memex_projects(new_value)
    ensure_memex_projects_can_be_enabled! if new_value
    @has_repository_memex_projects = new_value
  end

  def is_memex_projects_enabled?
    async_is_memex_projects_enabled?.sync
  end

  def async_is_memex_projects_enabled?
    async_owner.then do |owner|
      T.must(owner).organization? ? repository_memex_projects_enabled? && T.cast(owner, Organization).organization_projects_enabled? : repository_memex_projects_enabled?
    end
  end

  private def ensure_memex_projects_can_be_enabled
    if @has_repository_memex_projects && !can_enable_memex_projects?
      errors.add(:has_projects, "can't be enabled because the owning organization has projects disabled.")
    end
  end

  private def ensure_memex_projects_can_be_enabled!
    raise CannotEnableProjectsError unless can_enable_memex_projects?
  end

  # Public: returns count of memex projects linked to this repository
  #
  # Returns a number
  def open_memex_projects_count_for(viewer)
    return 0 unless memex_project_links.any?

    log_cache_hit = T.let(true, T::Boolean)
    count = GitHub.cache.fetch(open_memex_projects_count_cache_key_for(viewer)) do
      # if we're here, the cache missed
      log_cache_hit = false
      memex_projects_scope_for(viewer).open_projects.count
    end

    GitHub.dogstats.increment("open_memex_projects_count.cache.#{log_cache_hit ? "hit" : "miss"}", tags: ["action:open_memex_projects_count"])

    count
  end

  def open_memex_projects_count_cache_key_for(viewer)
    memexes_ids_hash = Digest::SHA256.hexdigest open_memex_projects_ids.join(",")
    "open_memex_projects_count:v1:#{self.id}:#{viewer&.id || "anon"}:#{memexes_ids_hash}"
  end

  def accessible_memexes_scope(scope, viewer, min_permission_level = "read", filter_ids: [])
    async_accessible_memexes_scope(scope, viewer, min_permission_level, filter_ids: filter_ids).sync
  end

  def async_accessible_memexes_scope(scope, viewer, min_permission_level = "read", filter_ids: [])
    self.async_owner.then do |owner|
      T.must(owner).accessible_memexes_scope(
        scope,
        viewer,
        min_permission_level,
        filter_ids: filter_ids
      )
    end
  end

  private

  def open_memex_projects_ids
    return @open_memex_projects_ids if defined?(@open_memex_projects_ids)

    memex_projects_ids = memex_project_links.pluck(:memex_project_id)
    @open_memex_projects_ids = MemexProject.where(id: memex_projects_ids).open_projects.order(:id).pluck(:id)
  end
end
