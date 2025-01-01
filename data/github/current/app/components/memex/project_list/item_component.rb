# typed: true
# frozen_string_literal: true

class Memex::ProjectList::ItemComponent < ApplicationComponent
  def initialize(context:, project:, owner:, is_recent_selected:, viewer_can_write:, team: nil)
    @context = context
    @project = project
    @owner = owner
    @is_recent_selected = is_recent_selected
    @viewer_can_write = viewer_can_write
    @team = team
  end

  memoize def show_memex_path
    case @owner
    when Organization
      show_org_memex_path(@owner, @project.number)
    when User
      show_user_memex_path(@owner, @project.number)
    end
  end

  memoize def project_dom_id
    "project_#{@project.id}"
  end

  memoize def icon
    return "project-template" if @project.is_template?
    "table"
  end

  memoize def label
    labels = []

    labels << "private" if !@project.public?
    labels << "template" if @project.is_template?

    labels.join(" ").capitalize
  end

  memoize def projects_dashboard_context?
    @context == MemexProject::ProjectsDashboardContext
  end

  private

  memoize def linker?
    [User, Organization].exclude?(@context)
  end
end
