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

  before_action :can_view_org_integrations?, only: [:index]
  before_action :can_view_integration?, only: [:show]
  before_action :can_edit_integration?, only: [:update, :permissions, :installations, :advanced, :update_permissions, :generate_key, :make_public, :make_private, :keys, :remove_key, :revoke_all_tokens, :transfer, :transfer_suggestions, :generate_client_secret, :remove_client_secret, :beta_features, :beta_toggle, :copilot, :update_copilot]
  before_action :can_delete_integration?, only: [:destroy]
  before_action :can_create_org_integrations?, only: [:new, :create]
  before_action :can_edit_org_integrations?, only: [:preview_note, :sign_agreement]

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
    ApplicationRecord::Lodge,
    only: [:advanced]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Iam,
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
    only: [:copilot]

  depends_on_clusters ApplicationRecord::Repositories,
    only: [:transfer_suggestions],
    optional: true

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:installations, :advanced, :keys, :new, :permissions, :show, :copilot],
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

    if Apps::ManagementHelper.can_update_all_apps?(on: current_context, actor: current_user)
      pending_transfers = current_context.inbound_integration_transfers.includes(:integration, :requester)
    else
      integrations = integrations.where(
        id: Apps::ManagementHelper.app_ids_directly_managed_by(actor: current_user, on: current_context),
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

  def can_view_org_integrations?
    render_404 unless Apps::ManagementHelper.can_view_any_app?(on: this_organization, actor: current_user)
  end

  def can_create_org_integrations?
    render_404 unless Apps::ManagementHelper.can_create_apps?(on: this_organization, actor: current_user)
  end

  def can_edit_org_integrations?
    render_404 unless Apps::ManagementHelper.can_update_all_apps?(on: this_organization, actor: current_user)
  end

  def can_view_integration?
    render_404 unless Apps::ManagementHelper.can_view?(app: current_integration, actor: current_user)
  end

  def can_edit_integration?
    render_404 unless Apps::ManagementHelper.can_edit?(app: current_integration, actor: current_user)
  end

  def can_delete_integration?
    render_404 unless Apps::ManagementHelper.can_delete?(app: current_integration, actor: current_user)
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
