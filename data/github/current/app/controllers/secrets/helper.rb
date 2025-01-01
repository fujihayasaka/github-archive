# typed: false
# frozen_string_literal: true

require "github/kredz_client"

module Secrets::Helper
  include GitHub::KredzClient
  extend ActiveSupport::Concern

  included do
    before_action :ensure_secrets_enabled
  end

  # Constants for rendering the secrets and variables lists
  ORG_SCOPE = "Organization"
  ORG_HOST_SETUP_SCOPE = "Host setup"
  ORG_DEVELOPMENT_ENV_SCOPE = "Development environment"
  ORG_PRIVATE_REGISTRY_SCOPE = "Private registry"
  REPO_SCOPE = "Repository"
  ENV_SCOPE = "Environment"
  CODESPACE_USER_SCOPE = "Codespace user"

  SECRET_MODE = "secret"
  VARIABLE_MODE = "variable"

  private

  def secrets_for(owner, app:)
    Secrets.for_app(app, owner: owner, actor: current_user)
  rescue Secrets::Error
    flash[:error] = "Failed to load secrets. Please refresh and try again."
    []
  end

  def secrets_for_repository(repository, actor, app:, fetch_environments: false)
    Secrets.for_repository(repository, actor: actor, app: app, fetch_environments: fetch_environments)
  rescue Secrets::Error
    flash[:error] = "Failed to load secrets. Please refresh and try again."
    {
      repository_secrets: [],
      organization_secrets: [],
      environment_secrets: [],
    }
  end

  def secret_count_for_environments(repository, app:, environments:)
    Secrets.secret_count_for_environments(repository, app: app, environments: environments)
  rescue Secrets::Error
    flash[:error] = "Failed to load secrets. Please refresh and try again."
    []
  end

  def github_public_key(owner, key_name:)
    return [1, GitHub.actions_secrets_public_key] if GitHub.enterprise?

    Secrets.github_public_key(owner: owner, key_name: key_name)
  end

  def decrypt_enterprise_secret(value)
    box = RbNaCl::Boxes::Sealed.from_private_key(Base64.decode64(GitHub.actions_secrets_private_key))
    box.decrypt(Base64.strict_decode64(value))
  end

  def ensure_secrets_enabled
    render_404 unless secrets_enabled?
  end

  def visibility_description_for_secret(secret, can_use_secrets_for_private_repos, is_enterprise)
    case secret.visibility
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS
      can_use_secrets_for_private_repos && "all repositories" || "public repositories"
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS
      is_enterprise && "private and internal repositories" || "private repositories"
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
      "#{secret.selected_repositories_count} #{"repository".pluralize(secret.selected_repositories_count)}"
    else
      ""
    end
  end

  def visibility_description_for_codespace_user_secret(secret)
    "#{secret.selected_repositories_count} #{"repository".pluralize(secret.selected_repositories_count)}"
  end

  def secrets_enabled?
    return @_app_enabled if defined?(@_app_enabled)

    org = defined?(current_organization) ? current_organization : nil
    @_app_enabled = Secrets::AppsHelper.secrets_enabled_for?(app_name, current_user, org:)
  end

  def app_name
    params[:app_name] || Secrets::AppsHelper::ACTIONS_APP_NAME
  end
end
