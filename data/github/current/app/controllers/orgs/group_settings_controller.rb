# typed: strict
# frozen_string_literal: true

class Orgs::GroupSettingsController < Orgs::Controller
  include GroupSettingsControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :repos_groups_enabled
  before_action :login_required
  before_action :ensure_admin_access

  allow_verified_fetch only: [:create, :update, :delete, :access_permissions_suggestions]

  protected

  sig { void }
  def repos_groups_enabled
    render_404 unless current_organization&.feature_flag_enabled?(:repos_groups, default: false)
  end

  sig { override.returns(Organization) }
  def group_organization
    current_organization
  end

  sig { override.returns(Symbol) }
  def selected_link
    :organization_group_settings
  end

  sig { override.returns(T::Boolean) }
  def read_only?
    false
  end

  private

  sig { void }
  def ensure_admin_access
    render_404 unless current_organization.adminable_by?(current_user)
  end
end
