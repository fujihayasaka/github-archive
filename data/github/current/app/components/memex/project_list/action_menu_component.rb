# typed: true
# frozen_string_literal: true

class Memex::ProjectList::ActionMenuComponent < ApplicationComponent
  extend T::Sig

  def initialize(context:, project:, owner:, is_recent_selected:, viewer_can_write:, team: nil)
    @context = context
    @project = project
    @owner = owner
    @is_recent_selected = is_recent_selected
    @viewer_can_write = viewer_can_write
    @team = team
  end

  sig { returns(T::Boolean) }
  def render?
    current_user.present?
  end

  sig { returns(T::Boolean) }
  def is_recent_selected?
    @is_recent_selected
  end

  sig { returns(T.nilable(String)) }
  memoize def update_memex_path
    case @owner
    when Organization
      update_org_memex_path(@owner, @project.number)
    when User
      update_user_memex_path(@owner, @project.number)
    end
  end

  sig { returns(T::Boolean) }
  memoize def disabled_unlink?
    !(team_admin_or_team_org_member? && project_admin?)
  end

  sig { returns(T::Boolean) }
  memoize def linker?
    [User, Organization].exclude?(@context)
  end

  sig { returns(T::Boolean) }
  def repository_context?
    @context == Repository
  end

  sig { returns(T::Boolean) }
  def team_context?
    @context == Team
  end

  sig { returns(T::Boolean) }
  memoize def projects_dashboard_context?
    @context == MemexProject::ProjectsDashboardContext
  end

  sig { returns(T::Boolean) }
  memoize def org_project?
    @owner.organization?
  end

  sig { returns(T::Boolean) }
  memoize def viewer_is_org_member_or_manager?
    current_user.member_or_billing_manager_for_any_organization?
  end

  def copy_project_content_attributes
    copy_project_hydro_attributes.merge(
      "show-dialog-id": "copy-project-dialog-#{@project.number}",
    )
  end

  def copy_as_template_content_attributes
    copy_as_template_hydro_attributes.merge(
      "show-dialog-id": "copy-as-template-dialog-#{@project.number}",
    )
  end

  private

  sig { returns(T::Boolean) }
  memoize def project_admin?
    @project.viewer_is_admin?(current_user)
  end

  memoize def team_admin_or_team_org_member?
    return false if @context != Team || @team.blank?
    return true if @team.adminable_by?(current_user)

    @team.member?(current_user) && @team.organization.member?(current_user)
  end

  def copy_project_hydro_attributes
    payload = {
      actor_id: current_user.id,
      project_id: @project.id,
    }

    hydro_click_tracking_attributes("memex_copy_project", payload)
  end

  def copy_as_template_hydro_attributes
    payload = {
      actor_id: current_user.id,
      project_id: @project.id,
      name: "copy_as_template",
      ui: "project_list",
    }

    hydro_click_tracking_attributes("memex_event", payload)
  end
end
