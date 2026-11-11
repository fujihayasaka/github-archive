# typed: true
# frozen_string_literal: true

class Memex::ProjectList::Blankslate::BlankslateContainerComponent < ApplicationComponent

  def initialize(
    context:,
    parsed_query:,
    owner:,
    is_org_empty: true,
    is_user_empty: true,
    has_no_projects: true,
    is_org_projects_disabled: false,
    has_search_filter: false,
    team: nil
  )
    @context = context
    @parsed_query = parsed_query
    @owner = owner
    @is_org_empty = is_org_empty
    @is_user_empty = is_user_empty
    @has_no_projects = has_no_projects
    @is_org_projects_disabled = is_org_projects_disabled
    @has_search_filter = has_search_filter
    @team = team
  end

  memoize def current_user_can_push?
    return false if @context != Repository

    helpers.current_user_can_push?
  end

  memoize def team_member?
    @context == Team && @team.member?(current_user)
  end

  memoize def org_project?
    @owner.is_a?(Organization)
  end

  memoize def member_or_current_user?
    org_member? || @owner.is_a?(User) && @owner == current_user
  end

  memoize def linker?
    [User, Organization, MemexProject::ProjectsDashboardContext].exclude?(@context)
  end

  memoize def user?
    @context == User
  end

  memoize def org?
    @context == Organization
  end

  memoize def org_member?
    @owner.is_a?(Organization) && @owner.member?(current_user)
  end

  memoize def projects_dashboard_context?
    @context == MemexProject::ProjectsDashboardContext
  end
end
