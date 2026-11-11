# typed: true
# frozen_string_literal: true

# Manages the ELM exporter's source/target PAT secrets for an organization.
#
# This is the *human* management UI counterpart to Api::OrganizationElmExporterSecrets:
# org admins (and holders of the ELM exporter secrets fine-grained permission) set the
# two PAT values that the privileged `elm_exporter_secrets` integration reads at runtime.
# Values are encrypted in the browser (sealed box against the org's public key) before they
# reach this controller and are never rendered back to the user.
class Orgs::ElmExporterSecretsController < Orgs::Controller
  include Secrets::Helper

  # Maps the Kredz secret name the ELM exporter consumes to the human-facing label.
  # Mirrors Api::OrganizationElmExporterSecrets::ALLOWED_SECRET_NAMES.
  SECRET_NAMES = {
    "SOURCE_PAT" => "Source PAT",
    "TARGET_PAT" => "Target PAT",
  }.freeze

  before_action :login_required
  before_action :ensure_elm_exporter_secrets_manageable
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :sudo_filter, only: [:update]

  javascript_bundle :settings

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Notify,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:index]

  def index
    public_key_id, public_key = github_public_key(current_organization, key_name: secrets_key_name)

    render "settings/organization/secrets/elm_exporter/index", locals: {
      public_key_id: public_key_id,
      public_key: public_key,
      configured_secret_names: configured_secret_names,
    }
  end

  def update
    secret_name = params[:name].to_s
    unless SECRET_NAMES.key?(secret_name)
      flash[:error] = "Unknown secret."
      return redirect_to settings_org_elm_exporter_secrets_path(current_organization)
    end

    public_key_id, = github_public_key(current_organization, key_name: secrets_key_name)

    if params[:encrypted_value].blank? || params[:key_id].to_i != public_key_id
      flash[:error] = "Failed to save #{SECRET_NAMES[secret_name]}. Please try again."
      return redirect_to settings_org_elm_exporter_secrets_path(current_organization)
    end

    validation = Credz.validate_org_secret(secret_name, params[:encrypted_value], GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS)
    unless validation.succeeded?
      flash[:error] = validation.error
      return redirect_to settings_org_elm_exporter_secrets_path(current_organization)
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_secret(params[:encrypted_value])
    else
      Secrets.embed(public_key_id, Base64.strict_decode64(params[:encrypted_value]))
    end

    Secrets.store(
      name: secret_name,
      app: secrets_app,
      owner: current_organization,
      actor: current_user,
      value: Base64.strict_encode64(value),
      visibility: GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS,
    )

    flash[:notice] = "#{SECRET_NAMES[secret_name]} saved."
    redirect_to settings_org_elm_exporter_secrets_path(current_organization)
  rescue Secrets::Error
    flash[:error] = "Failed to save #{SECRET_NAMES[secret_name]}. Please try again."
    redirect_to settings_org_elm_exporter_secrets_path(current_organization)
  end

  private

  # Overrides Secrets::Helper#app_name so secrets enablement and the secrets app
  # resolve to the ELM exporter integration rather than the default (actions).
  def app_name
    Secrets::AppsHelper::ELM_EXPORTER_APP_NAME
  end

  def secrets_app
    Secrets::AppsHelper.app_for(app_name, current_user, org: current_organization)
  end

  def secrets_key_name
    Secrets::AppsHelper.key_name_for(app_name, current_user)
  end

  def configured_secret_names
    # secrets_for (Secrets::Helper) already rescues Secrets::Error and returns [],
    # so this never raises.
    secrets_for(current_organization, app: secrets_app).map(&:name).to_set
  end

  def ensure_elm_exporter_secrets_manageable
    return render_404 if current_organization.nil?

    unless current_organization.adminable_by?(current_user) ||
        current_organization.can_write_organization_elm_exporter_secrets?(current_user)
      render_404
    end
  end
end
