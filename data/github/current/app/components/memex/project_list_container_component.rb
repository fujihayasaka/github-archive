# typed: true
# frozen_string_literal: true

class Memex::ProjectListContainerComponent < ApplicationComponent
  def initialize(project_owner:, display_legacy_org_warning: false, index_navigation_component_options:)
    @project_owner = project_owner
    @display_legacy_org_warning = display_legacy_org_warning
    @index_navigation_component_options = index_navigation_component_options
  end

  memoize def projects_beta_splash_and_banner_disabled?
    @project_owner && @project_owner.organization? && !@project_owner.organization_projects_enabled?
  end
end
