# typed: true
# frozen_string_literal: true

class Businesses::MemberRemovalController < Businesses::BusinessController

  before_action :login_required, only: [:destroy]
  before_action :ensure_self_removal_feature_enabled, only: [:destroy]
  before_action :ensure_self_removal_only, only: [:destroy]
  before_action :ensure_unaffiliated_member, only: [:destroy]

  depends_on_clusters ApplicationRecord::Mysql1,
                      ApplicationRecord::Configurations,
                      ApplicationRecord::IamAbilities,
                      ApplicationRecord::Collab,
                      ApplicationRecord::Billing,
                      ApplicationRecord::Accounts,
                      ApplicationRecord::Mysql2,
                      ApplicationRecord::Repositories

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::MemberRemovalController#destroy"
  ]

  # DELETE /enterprises/:slug/memberships/:username
  # Allow unaffiliated users to remove themselves from an enterprise
  def destroy
    # Remove the member (force: true allows self-removal without admin permissions)
    # This mirrors the logic in our RESTful API: Api::EnterpriseSelfRemoval
    this_business.remove_member(current_user, actor: current_user, force: true, reason: "self_removed")

    redirect_back(fallback_location: settings_path, notice: "You have been removed from the #{this_business.name} enterprise.")
  rescue Business::InvalidRemovalError => e
    redirect_back(fallback_location: settings_path, alert: "There was an error removing you from this enterprise.")
  end

  private

  def ensure_self_removal_feature_enabled
    return if FeatureFlag.vexi.enabled?("enable_enterprise_self_removal_for_unaffiliated_users", this_business, default: false)

    render_404
  end

  def ensure_self_removal_only
    return if params[:username] == current_user.display_login

    render_404
  end

  def ensure_unaffiliated_member
    return if this_business.exclusive_unaffiliated_member?(current_user)

    render_404
  end

  # CAP bypass: Self-removal should be allowed even under restrictive CAP policies
  # to ensure users can always remove themselves from enterprises they don't want to be part of
  def ip_allowlist_enforceable
    :no
  end

  def external_conditional_access_policy_enforceable
    :no
  end

  def require_active_external_identity_session?
    false
  end

  def two_factor_enforceable
    :no
  end
end
