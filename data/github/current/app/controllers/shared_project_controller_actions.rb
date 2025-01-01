# typed: false
# frozen_string_literal: true

module SharedProjectControllerActions
  def require_projects_enabled
    enabled = if current_repository
      current_repository.repository_projects_enabled?
    elsif this_organization
      this_organization.organization_projects_enabled?
    else
      true
    end
    render_404 unless enabled
  end

  def hide_spammy_projects
    return unless FeatureFlag.vexi.enabled?(:hide_classic_projects_for_spammy_users, default: true)

    render_404 if this_user&.spammy?
  end
end
