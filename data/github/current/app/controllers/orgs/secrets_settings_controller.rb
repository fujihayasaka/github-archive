# typed: true
# frozen_string_literal: true

class Orgs::SecretsSettingsController < Orgs::Controller
  include GitHub::Memoizer
  include Secrets::Helper
  include ActionView::Helpers::NumberHelper
  include ApplicationController::VerifiedFetchDependency
  include Organization::PermissionsDependency

  allow_verified_fetch only: [:remove_secret, :update_secret]

  before_action :login_required
  before_action :organization_admin_or_actions_secrets_fine_grained_permission
  before_action :ensure_trade_restrictions_allows_org_settings_access
  before_action :ensure_can_use_org_secrets, except: :index
  before_action :sudo_filter, only: [:remove_secret, :update_secret]

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

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:new_secret]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    ApplicationRecord::Notify,
    only: [:update_secret_page]

  VISIBILITIES = {
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS => {
      label: "All repositories",
      description: "This secret may be used by any repository in the organization.",
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS => {
      label: "Private repositories",
      description: "This secret may be used by any private repository in the organization.",
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This secret may only be used by specifically selected repositories.",
    }
  }.freeze

  ENTERPRISE_VISIBILITIES = {
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS => {
      label: "All repositories",
      description: "This secret may be used by any repository in the organization.",
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS => {
      label: "Private and internal repositories",
      description: "This secret may be used by any private or internal repository in the organization.",
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This secret may only be used by specifically selected repositories.",
    }
  }.freeze

  FREE_PLAN_VISIBILITIES = {
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS => {
      label: "Public repositories",
      description: "This secret may be used by public repositories in the organization.
      Paid GitHub plans include private repositories.",
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS => {
      label: "Private repositories",
      description: "Organization secrets cannot be used by private repositories with your plan.",
      disabled: true
    },
    GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS => {
      label: "Selected repositories",
      description: "This secret may only be used by specifically selected repositories.",
    }
  }.freeze

  def index
    secrets = secrets_for(current_organization, app: secrets_app).map do |secret|
      {
        name: secret.name,
        visibility_description: visibility_description_for_secret(secret, can_use_secrets_for_private_repos?, current_organization.business.present?),
        updated_at: Secrets.secret_updated_at(secret)
      }
    end

    edit_org_secret_urls = {}
    delete_org_secret_urls = {}
    secrets.each do |s|
      edit_org_secret_urls[s[:name]] = settings_org_secrets_update_secret_page_path(app_name:, name: s[:name])
      delete_org_secret_urls[s[:name]] = settings_org_secrets_remove_secret_path(app_name:, name: s[:name])
    end

    show_host_setup_secrets = current_organization.in_codespaces_salus_beta? && current_organization.feature_enabled?(:codespaces_host_setup_policy)
    if app_name == Secrets::AppsHelper::CODESPACES_APP_NAME && current_organization.feature_enabled?(:codespaces_dev_env_secrets)
      host_setup_secrets = if show_host_setup_secrets
        secrets_for(current_organization, app: Secrets::AppsHelper.app_for(Secrets::AppsHelper::CODESPACES_VM_SECRETS_APP_NAME, current_user)).map do |secret|
          {
            name: secret.name,
            visibility_description: visibility_description_for_secret(secret, can_use_secrets_for_private_repos?, current_organization.business.present?),
            updated_at: Secrets.secret_updated_at(secret)
          }
        end
      else
        []
      end

      edit_org_host_setup_secret_urls = {}
      delete_org_host_setup_secret_urls = {}
      host_setup_secrets.each do |s|
        edit_org_host_setup_secret_urls[s[:name]] = settings_org_secrets_update_secret_page_path(app_name:, name: s[:name], host_setup: true)
        delete_org_host_setup_secret_urls[s[:name]] = settings_org_secrets_remove_secret_path(app_name:, name: s[:name], host_setup: true)
      end

      render "settings/organization/secrets/codespaces_index", locals: {
        can_use_org_secrets: can_use_org_secrets?,
        can_use_secrets_for_private_repos: can_use_secrets_for_private_repos?,
        secrets:,
        host_setup_secrets:,
        show_host_setup_secrets: show_host_setup_secrets,
        edit_org_secret_urls:,
        delete_org_secret_urls:,
        edit_org_host_setup_secret_urls:,
        delete_org_host_setup_secret_urls:,
      }
    else
      can_write_org_actions_secrets = current_organization.can_write_organization_actions_secrets?(current_user)
      can_write_org_actions_variables = current_organization.can_write_organization_actions_variables?(current_user)

      # Metrics as part of https://github.com/github/actions-sudo/issues/475
      # Tracking how many users are accessing settings as non admins
      if current_organization.adminable_by?(current_user)
        GitHub.dogstats.increment("actions.org.settings.secrets_controller", tags: ["admin:true", "can_write_secrets:#{can_write_org_actions_secrets}", "can_write_variables:#{can_write_org_actions_variables}"])
      else
        GitHub.dogstats.increment("actions.org.settings.secrets_controller", tags: ["admin:false", "can_write_secrets:#{can_write_org_actions_secrets}", "can_write_variables:#{can_write_org_actions_variables}"])
      end

      if is_private_registry_secret?
        # Add the non-secret config data to the secret object so we can display it in the UI
        config_data = PrivateRegistry::Configuration.for_organization(current_organization).map { |c| [c.secret_name, c] }.to_h
        secrets = secrets.map do |secret|
          secret[:registry_data] = {
            type: PrivateRegistry::Configuration::HUMAN_READABLE_REGISTRY_TYPES[config_data[secret[:name]]&.registry_type&.to_sym],
            url: config_data[secret[:name]]&.url,
          }
          secret
        end

        render "settings/organization/secrets/private_registry/index", locals: {
          can_use_org_secrets: can_use_org_secrets?,
          can_use_secrets_for_private_repos: can_use_secrets_for_private_repos?,
          secrets:,
          edit_org_secret_urls:,
          delete_org_secret_urls:,
          view: Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user),
          can_write_organization_actions_secrets: can_write_org_actions_secrets,
          can_write_organization_actions_variables: can_write_org_actions_variables,
        }
      else
        render "settings/organization/secrets/index", locals: {
          can_use_org_secrets: can_use_org_secrets?,
          can_use_secrets_for_private_repos: can_use_secrets_for_private_repos?,
          secrets:,
          edit_org_secret_urls:,
          delete_org_secret_urls:,
          view: Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user),
          can_write_organization_actions_secrets: can_write_org_actions_secrets,
          can_write_organization_actions_variables: can_write_org_actions_variables,
        }
      end
    end
  end

  def new_secret # rubocop:todo GitHub/UseRestfulActions
    if can_use_secrets_for_private_repos?
      default_visibility = GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS
    else
      default_visibility = GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS
    end

    repositories = current_organization.repositories
    unless current_organization.plan.supports?(:private_secrets_and_variables)
      repositories = repositories.public_scope
    end

    if is_private_registry_secret?
      secret_view = Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user)
      render "settings/organization/secrets/private_registry/new", locals: {
        view: secret_view,
        visibilities:,
        default_visibility: can_use_secrets_for_private_repos? ? GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS : GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS,
        public_key: github_public_key(current_organization, key_name: secrets_key_name),
        total_count: repositories.count,
      }
    else
      render "settings/organization/secrets/new_secret", locals: {
        total_count: repositories.count,
        public_key: github_public_key(current_organization, key_name: secrets_key_name),
        visibilities: visibilities,
        default_visibility: default_visibility,
        can_use_secrets_for_private_repos: can_use_secrets_for_private_repos?,
        view: Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user),
        codespaces_host_setup: secret_for_codespaces_host_setup?,
      }
    end
  end

  def create_secret # rubocop:todo GitHub/UseRestfulActions
    id, encoded = github_public_key(current_organization, key_name: secrets_key_name)

    if params[:encrypted_value].empty? || params[:key_id].to_i != id
      flash[:error] = "Failed to add secret. Please try again."
      redirect_to settings_org_secrets_path
      return
    end

    name = params[:name]
    if is_private_registry_secret?
      unless params[:registry_type]
        flash[:error] = "Registry type selection is required. Please try again."
        redirect_to settings_org_secrets_path
        return
      end

      name = "#{params[:registry_type].upcase}_SECRET"
    end

    validation = Credz.validate_secret(name, params[:encrypted_value])
    unless validation.succeeded?
      flash[:error] = validation.error
      redirect_to settings_org_secrets_path
      return
    end

    value = if GitHub.enterprise?
      decrypt_enterprise_secret(params[:encrypted_value])
    else
      Secrets.embed(id, Base64.strict_decode64(params[:encrypted_value]))
    end

    encoded_value = Base64.strict_encode64(value)

    visibility = secret_for_codespaces_host_setup? ? GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS : params[:visibility]
    repository_node_ids = visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS.to_s ? Array(params[:repository_ids]) : []
    repository_ids = repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids).order(:id).map(&:global_relay_id)

    begin
      result = Secrets.create(
        name: name,
        app: secrets_app,
        owner: current_organization,
        actor: current_user,
        value: encoded_value,
        visibility: visibility.to_sym,
        selected_repositories: selected_repositories,
      )

      # Private registry configurations also need to save the related configuration information
      if is_private_registry_secret? && result&.stored
        configuration = PrivateRegistry::Configuration.new(
          owner: current_organization,
          owner_type: "Organization",
          registry_type: params[:registry_type],
          secret_name: name,
          url: params[:url],
          username: params[:username],
        )
        configuration.save!
      end
    rescue Secrets::Error => e
      if e.status == 400
        flash[:error] = "Failed to add secret, you've reached the #{number_with_delimiter(Credz::SECRET_ORG_MAX)} secret limit."
      elsif e.status == 409
        if is_private_registry_secret?
          flash[:error] = "Failed to add secret, a private registry with the same type (#{params[:registry_type]}) already exists."
        else
          flash[:error] = "Failed to add secret, a secret with the same name(#{params[:name].upcase}) already exists."
        end
      else
        flash[:error] = "Failed to add secret."
      end
    rescue ActiveRecord::ActiveRecordError => e
      if is_private_registry_secret?
        # There was an error saving a private registry's configuration and we should delete the secret
        Secrets.delete(name: name, owner: current_organization, actor: current_user, app: secrets_app)
        flash[:error] = "Failed to add secret. #{e.message}"
      end
    else
      flash[:notice] = "Secret added."
    end

    redirect_to settings_org_secrets_path
  end

  def remove_secret_partial # rubocop:todo GitHub/UseRestfulActions
    render_404 unless request.xhr?

    # We need to fetch the secret and check its visibility here.
    result = Secrets.fetch(
      name: params[:name],
      app: secrets_app,
      owner: current_organization,
      actor: current_user,
    )

    secret = result&.credential
    if secret&.visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
      selected_repositories = secret.selected_repositories.map(&:global_id).to_set
      selected_repository_ids = selected_repositories.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
      repositories = current_organization.repositories.where(id: selected_repository_ids)
    end

    render partial: "settings/organization/secrets/remove_secret",
           locals: {
              secret_name: params[:name],
              repositories: repositories,
              codespaces_host_setup: secret_for_codespaces_host_setup?
           }
  end

  def remove_secret # rubocop:todo GitHub/UseRestfulActions
    private_registry_config = if is_private_registry_secret?
      PrivateRegistry::Configuration.for_organization(current_organization).find_by(secret_name: params[:name])
    else
      nil
    end

    # Flash an error and do not delete secret if this is a private registry secret and deleting the configuration failed.
    if private_registry_config.present? && !private_registry_config.destroy
      flash[:error] = "Failed to delete secret."
      redirect_to settings_org_secrets_path
      return
    end

    begin
      result = Secrets.delete(
        name: params[:name],
        app: secrets_app,
        owner: current_organization,
        actor: current_user,
      )
    rescue Secrets::Error
    end

    if !result&.success
      # Something went wrong - Save the config since the secret hasn't yet been deleted in Credz.
      PrivateRegistry::Configuration.new(private_registry_config.attributes).save if private_registry_config
      flash[:error] = "Failed to delete secret."
    else
      flash[:notice] = "Secret deleted."
    end

    redirect_to settings_org_secrets_path
  end

  def update_secret # rubocop:todo GitHub/UseRestfulActions
    id, encoded = github_public_key(current_organization, key_name: secrets_key_name)

    encoded_value = ""
    unless params[:encrypted_value].empty?
      if params[:key_id].to_i != id
        flash[:error] = "Failed to update secret. Please try again."
        redirect_to settings_org_secrets_path
        return
      end

      validation = Credz.validate_secret(params[:name], params[:encrypted_value])
      unless validation.succeeded?
        flash[:error] = validation.error
        redirect_to settings_org_secrets_path
        return
      end

      value = if GitHub.enterprise?
        decrypt_enterprise_secret(params[:encrypted_value])
      else
        Secrets.embed(id, Base64.strict_decode64(params[:encrypted_value]))
      end

      encoded_value = Base64.strict_encode64(value)
    end

    visibility = secret_for_codespaces_host_setup? ? GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS : params[:visibility]
    repository_node_ids = visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS.to_s ? Array(params[:repository_ids]) : []
    repository_ids = repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids).order(:id).map(&:global_relay_id)

    begin
      result = Secrets.update(
        name: params[:name],
        app: secrets_app,
        owner: current_organization,
        actor: current_user,
        value: encoded_value,
        visibility: visibility.to_sym,
        selected_repositories: selected_repositories,
      )

      if is_private_registry_secret? && result&.updated
        PrivateRegistry::Configuration.for_organization(current_organization).find_by(secret_name: params[:name])&.update!(
          url: params[:url],
          username: params[:username],
          registry_type: params[:registry_type],
        )
      end
    rescue Secrets::Error => e
      flash[:error] = "Failed to update secret."
    rescue ActiveRecord::ActiveRecordError => e
      if is_private_registry_secret?
        flash[:error] = "Failed to update registry configuration. #{e.message}"
      end
    else
      flash[:notice] = "Secret updated."
    end

    redirect_to settings_org_secrets_path
  end

  def update_secret_page # rubocop:todo GitHub/UseRestfulActions
    begin
      result = Secrets.fetch(
        name: params[:name],
        app: secrets_app,
        owner: current_organization,
        actor: current_user,
      )
    rescue Secrets::Error
      return render_404
    end

    secret = result.credential
    return render_404 unless secret

    selected_repository_node_ids = secret.selected_repositories.map(&:global_id).to_set
    repository_ids = selected_repository_node_ids.map { |global_id| Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] }
    selected_repositories = current_organization.repositories.where(id: repository_ids)

    selected_repository_global_ids = selected_repositories.map(&:global_relay_id).to_set

    repositories = current_organization.repositories
    unless current_organization.plan.supports?(:private_secrets_and_variables)
      repositories = repositories.public_scope
    end

    if is_private_registry_secret?
      configuration = PrivateRegistry::Configuration.for_organization(current_organization).find_by(secret_name: params[:name])
      return render_404 unless configuration

      secret_view = Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user)
      render "settings/organization/secrets/private_registry/update", locals: {
        view: secret_view,
        secret:,
        configuration:,
        visibilities: visibilities,
        default_visibility: can_use_secrets_for_private_repos? ? GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS : GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS,
        public_key: github_public_key(current_organization, key_name: secrets_key_name),
        total_count: repositories.count,
      }
    else
      render "settings/organization/secrets/update_secret", locals: {
        public_key: github_public_key(current_organization, key_name: secrets_key_name),
        secret: secret,
        repositories: selected_repositories,
        selected_repositories: selected_repository_global_ids,
        total_count: repositories.count - selected_repositories.count,
        selected_visibility: secret.visibility,
        visibilities: visibilities,
        can_use_secrets_for_private_repos: can_use_secrets_for_private_repos?,
        codespaces_host_setup: secret_for_codespaces_host_setup?,
        view: Settings::Organization::SecretsView.new(app_name: app_name, current_organization: current_organization, current_user: current_user),
      }
    end
  end

  protected

  # trace_web_request is a before action callback provided by ApplicationController::StatsDependency that adds
  # attributes for the current request to the current span. Here we override in order to add additional
  # attributes that are specific to this controller.
  def trace_web_request
    GitHub.current_span&.set_attribute("gh.integration.name", app_name) if app_name.present?
    super
  end

  private

  def ensure_can_use_org_secrets
    render_404 unless can_use_org_secrets?
  end

  def can_use_org_secrets?
    current_organization.can_use_org_secrets?
  end

  def can_use_secrets_for_private_repos?
    return true if app_name == Secrets::AppsHelper::DEPENDABOT_APP_NAME

    current_organization.plan.supports?(:private_secrets_and_variables)
  end

  def visibilities
    if can_use_secrets_for_private_repos?
      current_organization.business.present? ? ENTERPRISE_VISIBILITIES : VISIBILITIES
    else
      FREE_PLAN_VISIBILITIES
    end
  end

  memoize def secrets_app
    if secret_for_codespaces_host_setup?
      Secrets::AppsHelper.app_for(Secrets::AppsHelper::CODESPACES_VM_SECRETS_APP_NAME, current_user)
    else
      Secrets::AppsHelper.app_for(app_name, current_user, org: current_organization)
    end
  end

  memoize def secrets_key_name
    if secret_for_codespaces_host_setup?
      Secrets::AppsHelper.key_name_for(Secrets::AppsHelper::CODESPACES_VM_SECRETS_APP_NAME, current_user)
    else
      Secrets::AppsHelper.key_name_for(app_name, current_user)
    end
  end

  memoize def secret_for_codespaces_host_setup?
    app_name == Secrets::AppsHelper::CODESPACES_APP_NAME &&
      ActiveModel::Type::Boolean.new.cast(params[:host_setup]) &&
      (current_organization.in_codespaces_salus_beta? && current_organization.feature_enabled?(:codespaces_host_setup_policy))
  end

  def is_private_registry_secret?
    app_name == Secrets::AppsHelper::PRIVATE_REGISTRY_APP_NAME
  end
end
