# typed: true
# frozen_string_literal: true

class Memex::ProjectListContainerComponent < ApplicationComponent
  def initialize(project_owner:, repository: nil, display_legacy_org_warning: false, index_navigation_component_options:)
    @project_owner = project_owner
    @repository = repository
    @display_legacy_org_warning = display_legacy_org_warning
    @index_navigation_component_options = index_navigation_component_options
  end

  memoize def projects_beta_splash_and_banner_disabled?
    @project_owner && @project_owner.organization? && !@project_owner.organization_projects_enabled?
  end

  def pinned_views_sidebar_enabled?
    return false unless @repository

    PinnedViewsFeature.enabled?(@repository, actor: current_user)
  end

  def collapsible_sidebar_enabled?
    return false unless pinned_views_sidebar_enabled?

    # Check against current_user only — must match the JS-side check in
    # client_side_feature_flags which also only checks the user actor.
    FeatureFlag.vexi.enabled?(:issues_react_collapsible_sidebar, current_user, default: false)
  end

  def sidebar_props
    return {} unless @repository

    {
      owner: @repository.owner.display_login,
      repo: @repository.name,
      hasProjectsEnabled: true,
    }
  end
end
