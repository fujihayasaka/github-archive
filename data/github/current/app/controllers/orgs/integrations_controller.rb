# typed: true
# frozen_string_literal: true

class Orgs::IntegrationsController < Orgs::Controller
  # Even though the new_from_manifest action is a POST, it is idempotent and merely presents
  # the user with a view without making any changses to the database. Since the client side POST
  # is initiated from a host that is not GitHub, we can't authorize EMU actors to determine if
  # the organization should be visible for the request.
  #
  # We redirect regardless of Organization existence and handle authorization in the subsequent
  # request which will have the required cookies for authorization.
  skip_before_action :this_organization_required, only: [:receive_manifest]

  # See the above comment for the reason this is needed.
  ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS = %w(receive_manifest)

  include IntegrationsControllerMethods
  include IntegrationManagerHelper

  before_action :require_any_app_manager, only: [:index]
  before_action :require_current_app_manager, only: [:show, :update, :permissions, :installations, :advanced, :update_permissions, :generate_key, :make_public, :make_private, :destroy, :keys, :remove_key, :revoke_all_tokens, :transfer, :generate_client_secret, :remove_client_secret, :beta_features, :beta_toggle, :agent, :update_agent]
  before_action :require_all_apps_manager, except: [:index, :show, :update, :permissions, :installations, :advanced, :update_permissions, :generate_key, :make_public, :make_private, :destroy, :keys, :remove_key, :revoke_all_tokens, :transfer, :generate_client_secret, :remove_client_secret, :beta_features, :beta_toggle, :receive_manifest, :agent, :update_agent]

  # Even though the new_from_manifest action is a POST, it is idempotent and merely presents
  # the user with a view without making any changses to the database. Since the client side POST
  # is initiated from a host that is not GitHub, CSRF checks need to be disabled.
  skip_before_action :verify_authenticity_token, only: [:receive_manifest]

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

  def index
    integrations = current_context.integrations.not_for_github_connect

    if manages_all_integrations?(user: current_user, owner: current_context)
      pending_transfers = current_context.inbound_integration_transfers.includes(:integration, :requester)
    else
      integrations = integrations.where(
        id: Permissions::Enumerator.subject_ids_for_permission(action: :manage_app, actor_id: current_user.id),
      )
    end
    integrations = integrations.order("integrations.name asc").paginate(page: current_page, per_page: 15)

    view = create_view_model(
      Integrations::IndexView,
      integrations: integrations,
      pending_transfers: pending_transfers,
      owner: current_context
    )
    render "integrations/settings/index", locals: { view: view }
  end

  private

  # receive_manifest always results in a redirect to /login so it is safe to
  # skip the private mode check
  def enforce_multi_tenant_private_mode?
    return false if action_name == "receive_manifest"

    super
  end

  def current_context
    this_organization
  end

  def require_all_apps_manager
    render_404 unless manages_all_integrations?(user: current_user, owner: this_organization)
  end

  def require_any_app_manager
    render_404 unless manages_any_integration?(user: current_user, organization: this_organization)
  end

  def require_current_app_manager
    render_404 unless manages_integration?(user: current_user, integration: current_integration)
  end

  def emu_visibility_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS.include?(action_name)
    :yes
  end

  def tenant_verification_enforceable
    return :no if ACTIONS_EXCLUDED_FROM_EMU_VISIBILITY_CHECKS.include?(action_name)
    :yes
  end
end
