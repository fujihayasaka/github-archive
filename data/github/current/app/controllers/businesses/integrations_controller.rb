# typed: true
# frozen_string_literal: true

class Businesses::IntegrationsController < Businesses::BusinessController
  # Even though the new_from_manifest action is a POST, it is idempotent and merely presents
  # the user with a view without making any changes to the database. Since the client side POST
  # is initiated from a host that is not GitHub, we can't authorize EMU actors to determine if
  # the business should be visible for the request.
  #
  # We redirect regardless of Business existence and handle authorization in the subsequent
  # request which will have the required cookies for authorization.
  #
  # TODO: ecosystem-apps/issues/5723 test the manifest flow and potentially uncomment the line below. Although
  # this_business_required is not defined yet. Might need to find the "right" helper.
  # skip_before_action :this_business_required, only: [:receive_manifest]

  # See the above comment for the reason this is needed.
  ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS = %w(receive_manifest)

  include IntegrationsControllerMethods
  include IntegrationManagerHelper

  before_action :check_feature_flag
  before_action :require_any_app_manager, only: [:index]
  before_action :require_current_app_manager, only: [:show, :update, :permissions, :installations, :advanced, :update_permissions, :generate_key, :make_public, :make_private, :destroy, :keys, :remove_key, :revoke_all_tokens, :transfer, :generate_client_secret, :remove_client_secret, :beta_features, :beta_toggle, :agent, :update_agent]
  before_action :require_all_apps_manager, except: [:index, :show, :update, :permissions, :installations, :advanced, :update_permissions, :generate_key, :make_public, :make_private, :destroy, :keys, :remove_key, :revoke_all_tokens, :transfer, :generate_client_secret, :remove_client_secret, :beta_features, :beta_toggle, :receive_manifest, :agent, :update_agent]

  # Even though the new_from_manifest action is a POST, it is idempotent and merely presents
  # the user with a view without making any changses to the database. Since the client side POST
  # is initiated from a host that is not GitHub, CSRF checks need to be disabled.
  # skip_before_action :verify_authenticity_token, only: [:receive_manifest]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:advanced]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Permissions,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Lodge,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:installations]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:keys]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:permissions]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:show]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Lodge,
    only: [:agent]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:installations, :advanced, :keys, :new, :permissions, :show, :agent],
    optional: true

  # In order to make the manifests flow work on instances that run with private mode enabled,
  # we have to disable the guard for this action so that we get the chance to register
  # the manifests payload in the KV and cookies.
  if GitHub.enterprise?
    skip_before_action :enforce_private_mode, only: [:receive_manifest], if: -> { GitHub.private_mode_enabled? }
  end

  javascript_bundle :settings

  # TODO: ecosystem-apps/issues/5723 do we need a custom index just like orgs?
  # app/controllers/orgs/integrations_controller.rb:134

  private

  # receive_manifest always results in a redirect to /login so it is safe to
  # skip the private mode check
  def enforce_multi_tenant_private_mode?
    return false if action_name == "receive_manifest"

    super
  end

  def current_context
    this_business
  end

  def require_all_apps_manager
    # TODO: ecosystem-apps/issues/5723 add proper permissions check support here
    # render_404 unless manages_all_integrations?(user: current_user, owner: this_business)
    render_404 unless this_business.adminable_by?(current_user)
  end

  def require_any_app_manager
    # TODO: ecosystem-apps/issues/5723 add proper permissions check support here
    # render_404 unless manages_any_integration?(user: current_user, organization: this_business)
    render_404 unless this_business.adminable_by?(current_user)
  end

  def require_current_app_manager
    # TODO: ecosystem-apps/issues/5723 add proper permissions check support here
    # render_404 unless manages_integration?(user: current_user, integration: current_integration)
    render_404 unless this_business.adminable_by?(current_user)
  end

  def emu_visibility_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS.include?(action_name)
    :yes
  end

  def tenant_verification_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS.include?(action_name)
    :yes
  end

  def check_feature_flag
    render_404 unless GitHub.flipper[:enterprise_owned_app_management].enabled?(this_business)
  end

  def current_integration
    raise ActiveRecord::RecordNotFound if super.connect_app?
    super
  end
end
