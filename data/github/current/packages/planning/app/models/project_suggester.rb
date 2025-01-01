# typed: true
# frozen_string_literal: true

# ProjectSuggester provides lists of projects based off a context. This is useful
# cases like the Issue sidebar, when we need to provide a list of potential projects
# to add the issue to.
#
# viewer:  - The User who is viewing the projects. We only suggest projects that the viewer
#           has write access to
# context: - An Owner, Repository or Issue that the scope the list of suggested projects.
# load_memex_projects: - Whether or not to load org and user memex projects (default: false)
# only_memex_templates: - Whether or not we want to only return memex projects which are templates when load_memex_projects is true (default: false)
# load_classic_projects: - Whether or not to load classic projects (default: true)
class ProjectSuggester
  include MemexesHelper

  ORG_PROJECT_RESULTS_LIMIT = 500

  def initialize(viewer:, context:, load_memex_projects: false, only_memex_templates: false, load_classic_projects: true)
    @viewer = viewer
    @context = context
    @load_memex_projects = load_memex_projects
    @only_memex_templates = only_memex_templates
    @load_classic_projects = load_classic_projects
  end

  def load_memex_projects?
    @load_memex_projects
  end

  def only_memex_templates?
    @only_memex_templates
  end

  def load_classic_projects?
    @load_classic_projects
  end

  def repository_projects(min_permission_level: "write")
    return [] if repository.nil?
    return @repository_projects if defined?(@repository_projects)

    @repository_projects = []

    if load_classic_projects?
      track_execution_time(["method:repository_projects"]) do
        permission_check = min_permission_level == "read" ? "readable_by?" : "writable_by?"
        @repository_projects = if repository.public_send(permission_check, @viewer)
          repository.projects.open_projects.order("projects.name ASC").includes(:owner).to_a
        else
          []
        end
      end
    end

    if load_memex_projects?
      @repository_projects = (@repository_projects + repository_memex_projects(min_permission_level: min_permission_level)).sort_by(&:name)
    end

    @repository_projects
  end

  def repository_memex_projects(min_permission_level: "write", order_by: nil)
    track_execution_time(["method:repository_memex_projects"]) do
      scope = async_repository_memex_projects_scope(@viewer, min_permission_level, order_by: order_by)
      scope.sync.includes(:owner).to_a
    end
  end

  def organization_projects(min_permission_level: "write")
    return @organization_projects if defined?(@organization_projects)

    @organization_projects = []

    if organization
      if load_classic_projects?
        track_execution_time(["method:organization_projects"]) do
          scope = if min_permission_level == "read"
            organization.visible_projects_for(@viewer)
          else
            organization.writable_projects_for(@viewer).prefer_linked_to(repository)
          end

          @organization_projects = scope.open_projects.order("projects.name ASC").includes(:owner).to_a
        end
      end

      if load_memex_projects?
        track_execution_time(["method:organization_memex_projects", "only_memex_templates:#{only_memex_templates?}"]) do
          memex_open_projects = organization.memex_projects.open_projects
          if only_memex_templates?
            memex_open_projects = memex_open_projects.templates
          end

          accessible_memexes = organization.accessible_memexes_scope(memex_open_projects, @viewer, min_permission_level)
          memex_projects = accessible_memexes.includes(:owner).to_a

          @organization_projects = (@organization_projects + memex_projects).sort_by(&:name)
        end
      end
    end

    @organization_projects
  end

  def user_projects(min_permission_level: "write")
    return @user_projects if defined?(@user_projects)

    @user_projects = []

    if organization
      @user_projects = Project.none
    else
      if load_classic_projects?
        track_execution_time(["method:user_projects"]) do
          scope = if min_permission_level == "read"
            repository.owner.visible_projects_for(@viewer)
          else
            repository.owner.writable_projects_for(@viewer).prefer_linked_to(repository)
          end
          @user_projects = scope.open_projects.order("projects.name ASC").includes(:owner).to_a
        end
      end
      if load_memex_projects?
        # Do not need to perform template filtering for user projects as users cannot have templates
        track_execution_time(["method:user_memex_projects"]) do
          memex_open_projects = owner.memex_projects.open_projects
          accessible_memexes = owner.accessible_memexes_scope(memex_open_projects, @viewer, min_permission_level)
          memex_projects = accessible_memexes.includes(:owner).to_a
          @user_projects = (@user_projects + memex_projects).sort_by(&:name)
        end
      end
    end

    @user_projects
  end

  # Returns the  for the viewer dependent on permission level
  # and the resolved repository context in which the suggester is called
  #
  # min_permission_level :- The minimum permission level the viewer must have against the repository
  # include_repo_linked  :- Whether or not to include memex projects that are linked to the repository
  #
  def recent_projects(min_permission_level: "write", include_repo_linked: false)
    return @recent_projects if defined? @recent_projects
    return [] if @viewer.nil?

    @recent_projects = []
    if load_classic_projects?
      track_execution_time(["method:recent_projects"]) do
        sql = []
        args = []

        permission_check = min_permission_level == "read" ? "readable_by?" : "writable_by?"
        if repository.public_send(permission_check, @viewer)
          # Only include repository-owned projects if the user has write access
          # to the repository, since projects inherit their repositories'
          # permissions.
          sql << "(projects.owner_type = ? AND projects.owner_id = ?)"
          args.concat(["Repository", repository.id])
        end

        if organization
          # We need to interpolate ActiveRecord-generated SQL here, so that we
          # can effectively get a subquery into this. If you're modifying this
          # code, please keep this query generated by ActiveRecord, so that we
          # can rely on it being safely sanitized for user input.

          permission_check = min_permission_level == "read" ? "visible_projects_for" : "writable_projects_for"
          org_project_ids_query = organization.public_send(permission_check, @viewer).select("projects.id").to_sql
          sql << "(projects.id IN (#{org_project_ids_query}))"
        end

        if repository.owner.instance_of?(User)
          owner = repository.owner
          permission_check = min_permission_level == "read" ? "visible_projects_for" : "writable_projects_for"
          user_project_ids_query = owner.public_send(permission_check, @viewer).select("projects.id").to_sql
          sql << "(projects.id IN (#{user_project_ids_query}))"
        end

        if sql.any?
          scope = Project.select("projects.*, MAX(project_cards.updated_at) AS updated_max")
            .where(sql.join(" OR "), *args)
            .open_projects
            .joins(:cards)
            .where("project_cards.creator_id = ?", @viewer.id)

          if load_memex_projects?
            scope = scope.where("project_cards.updated_at >= ?", 15.days.ago)
          end

          @recent_projects.concat(
            scope
              .order("updated_max DESC") # Get the projects with the most recently modified cards
              .limit(10)
              .group(:id)
              .includes(:owner)
              .to_a,
          )
        end
      end
    end

    if load_memex_projects?
      track_execution_time(["method:recent_memex_projects"]) do
        @recent_projects = recent_memex_projects(min_permission_level: min_permission_level) + @recent_projects
        if include_repo_linked
          @recent_projects = @recent_projects + repository_memex_projects(min_permission_level: min_permission_level, order_by: { updated_at: :desc })
        end
      end
    end

    @recent_projects.uniq
  end

  def recent_memex_projects(min_permission_level: "write", auth_method: :enumeration)
    return [] if @viewer.nil?
    async_recent_memex_projects(min_permission_level: min_permission_level, auth_method: auth_method).sync
  end

  def async_recent_memex_projects(min_permission_level: "write", auth_method: :enumeration, limit: 10)
    @recent_memex_projects ||= begin
      return Promise.resolve([]) unless load_memex_projects?

      async_owner.then do |owner|
        scope = owner.memex_projects.open_projects
        if only_memex_templates?
          scope = scope.templates
        end

        owner.async_accessible_memexes_scope(
          scope,
          @viewer,
          min_permission_level,
          auth_method
        ).then do |memex_projects|
          memex_projects
            .joins(:memex_project_visits).where("memex_project_visits.viewer_id = ?", @viewer.id)
            .order("memex_project_visits.last_visited_at DESC", number: :desc)
            .limit(limit)
            .group(:id)
            .includes(:owner)
            .to_a
        end
      end
    end
  end

  def async_repository_memex_projects_scope(viewer, min_permission_level, order_by: nil)
    return Promise.resolve(MemexProject.none) if repository.memex_project_links.empty?

    scope = repository.memex_project_links
    if only_memex_templates?
      scope = scope.joins(:memex_project).merge(MemexProject.templates)
    end

    memex_project_ids = scope.pluck(:memex_project_id)
    repository.async_owner.then do |owner|
      memexes = owner.memex_projects.where("id IN (?)", memex_project_ids).open_projects

      unless order_by.nil?
        memexes = memexes.order(order_by)
      end

      memexes = owner.async_accessible_memexes_scope(
        memexes,
        viewer,
        min_permission_level
      )
    end
  end

  private

  def repository
    async_repository.sync
  end

  def async_repository
    return Promise.resolve(@repository) if defined? @repository

    @repository = case @context
    when Issue then @context.async_repository.then { |repo| repo }
    when Repository then @context
    else nil
    end

    Promise.resolve(@repository)
  end

  def owner
    return @owner if defined? @owner
    @owner = async_owner.sync
  end

  def async_owner
    case @context
    when Issue then
      @context.async_repository.then { |repo| repo.async_owner }
    when Repository then
      @context.async_owner
    when Team then
      @context.async_organization
    else
      Promise.resolve(@context)
    end
  end

  def organization
    return @organization if defined?(@organization)
    @organization = if @context.is_a?(Organization)
      @context
    elsif @context.is_a?(Team)
      @context.owner
    else
      repository.in_organization? && repository.owner.is_a?(Organization) ? repository.owner : nil
    end
  end

  def track_execution_time(tags)
    timer = Timer.start
    result = yield
    GitHub.dogstats.distribution("project_suggester.dist.time", timer.elapsed_ms, tags: tags)
    result
  end
end
