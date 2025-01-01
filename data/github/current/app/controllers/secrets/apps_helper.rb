# typed: true
# frozen_string_literal: true

module Secrets::AppsHelper

  # GitHub apps with org and repo secret management integration.
  ACTIONS_APP_NAME = "actions"
  DEPENDABOT_APP_NAME = "dependabot"
  CODESPACES_APP_NAME = "codespaces"
  CODESPACES_VM_SECRETS_APP_NAME = "codespaces_vm_secrets"
  PRIVATE_REGISTRY_APP_NAME = "private_registries"
  BYOK_CUSTOM_MODELS_APP_NAME = "byok_custom_models"
  COPILOT_BYOK_APP_NAME = "copilot_byok"
  ELM_EXPORTER_APP_NAME = "elm_exporter"

  # A list of apps that are enabled and visible to the current user.
  def self.enabled_app_names(user, org: nil)
    secrets_app_info_hash(user, org:).filter_map { |app_name, app_info| app_name if app_info[:enabled] }.sort
  end

  def self.secrets_enabled_for?(app_name, user, org: nil)
    !!secrets_app_info_hash(user, org:).dig(app_name, :enabled)
  end

  def self.multi_integrations_enabled_for_user?(user)
    GitHub.dependabot_enabled? || user&.codespaces_feature_enabled?
  end

  def self.display_name_for(app_name)
    return "Private registries" if app_name == PRIVATE_REGISTRY_APP_NAME
    app_name.capitalize
  end

  def self.page_title_for(app_name, user)
    return "Secrets" unless multi_integrations_enabled_for_user?(user)

    "#{display_name_for(app_name)} secrets"
  end

  def self.highlight_for(app_name, user)
    return :secrets unless multi_integrations_enabled_for_user?(user)

    "secrets_settings_#{app_name}".to_sym
  end

  def self.app_for(app_name, user, org: nil)
    secrets_app_info_hash(user, org:).dig(app_name, :app)
  end

  def self.key_name_for(app_name, user)
    secrets_app_info_hash(user).dig(app_name, :key_name)
  end

  def self.secrets_app_info_hash(user, org: nil)
    {
      ACTIONS_APP_NAME => {
        app: GitHub.launch_github_app, # Always store secrets with the prod app, even in Launch lab.
        enabled: GitHub.actions_enabled?,
        key_name: Platform::EncryptionKeys::CUSTOM_TASKS,
      },
      DEPENDABOT_APP_NAME => {
        app: GitHub.dependabot_github_app, # Tip: Run bin/create-dependabot-github-app.rb for local dev.
        enabled: GitHub.dependabot_enabled?,
        key_name: Platform::EncryptionKeys::DEPENDABOT_SECRETS,
      },
      CODESPACES_APP_NAME => {
        app: Apps::Privileged.integration(:codespaces_production),  # Tip: Run bin/setup-codespaces for local dev.
        enabled: user&.codespaces_feature_enabled?,
        key_name: Platform::EncryptionKeys::CODESPACES_SECRETS,
      },
      CODESPACES_VM_SECRETS_APP_NAME => {
        app: Apps::Privileged.integration(:codespaces_vm_secrets),  # Tip: Run bin/setup-codespaces for local dev.
        enabled: false,
        key_name: Platform::EncryptionKeys::CODESPACES_VM_SECRETS
      },
      PRIVATE_REGISTRY_APP_NAME => {
        app: Apps::Privileged.integration(:private_registry_secrets),  # Tip: Run bin/create-private-registry-secrets-app for local dev.
        enabled: GitHub.actions_enabled?,
        key_name: Platform::EncryptionKeys::PRIVATE_REGISTRY_SECRETS,
      },
      BYOK_CUSTOM_MODELS_APP_NAME => {
        app: Apps::Privileged.integration(:byok_custom_models),  # Tip: Run bin/create-byok-custom-models-app for local dev.
        enabled: false, # We do not want to show this in the generic secrets settings page
        key_name: Platform::EncryptionKeys::BYOK_CUSTOM_MODELS_SECRETS,
      },
      COPILOT_BYOK_APP_NAME => {
        app: Apps::Privileged.integration(:copilot_byok),  # Tip: Run bin/create-copilot-byok-app for local dev.
        enabled: false, # We do not want to show this in the generic secrets settings page
        key_name: Platform::EncryptionKeys::COPILOT_BYOK_SECRETS,
      },
      ELM_EXPORTER_APP_NAME => {
        app: Apps::Privileged.integration(:elm_exporter_secrets),
        enabled: false, # We do not want to show this in the generic secrets settings page
        key_name: Platform::EncryptionKeys::ELM_EXPORTER_SECRETS,
      },
    }
  end

  private_class_method :secrets_app_info_hash
end
