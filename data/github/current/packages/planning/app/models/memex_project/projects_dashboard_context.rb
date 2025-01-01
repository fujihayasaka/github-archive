# typed: true
# frozen_string_literal: true

class MemexProject

  # Wrapper class used in MemexesController to act as a `source` for the ProjectListDependency
  class ProjectsDashboardContext
    include MemexProject::SharedMemexProjectsDependency

    CAP_FILTER_BUFFER = 20

    def initialize(user)
      @user = user
    end

    # Return an ActiveRecord scope for all projects created by this user
    def memex_projects
      @user.created_memex_projects
    end

    def accessible_memexes_scope(*args, **kwargs)
      @user.accessible_memexes_scope(*args, **kwargs)
    end

    # Overrides SharedMemexProjectsDependency, to instead:
    # * use `recenty_visited_memex_projects`, instead of `.memex_projects`
    sig { params(viewer: T.nilable(User), cap_filter: T.nilable(ConditionalAccess::Filter), limit: Integer).returns(T.nilable(ActiveRecord::Relation)) }
    def recently_visited_projects(viewer:, cap_filter:, limit: 20)
      return if viewer.nil?
      # Query for open projects visited by the user
      recently_visited_projects = viewer.recently_visited_memex_projects.open_projects.preload(:owner)

      # Sends user's visited projects to Authzd to ensure that user still has read access to them
      recently_visited_projects = accessible_memexes_scope(recently_visited_projects, viewer, "read", :batching)

      should_cap_filter = viewer.feature_enabled?(:cap_filter_projects_dashboard) && cap_filter.present?

      # Returns a list of recently viewed projects for display that the user has read access to
      ordered_projects = recently_visited_projects
        .order("memex_project_visits.last_visited_at DESC", number: :desc)
        .limit(limit + (should_cap_filter ? CAP_FILTER_BUFFER : 0))

      cap_filtered_projects = if should_cap_filter
        authorized_ids = cap_filter.authorized_resources(ordered_projects).pluck(:id)
        ordered_projects.where(id: authorized_ids).limit(limit)
      else
        ordered_projects
      end
      cap_filtered_projects.preload(:latest_status_update)
    end

    # Some stubbed methods that should probably be addressed by changing template logic instead

    def projects
      []
    end

    def organization?
      false
    end

  end

end
