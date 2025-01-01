# typed: true
# frozen_string_literal: true

class Stafftools::Organizations::PrivateRegistries::IndexComponent < ApplicationComponent
  def initialize(organization:, configurations:, secrets:)
    @organization = organization
    @configurations = configurations
    @secrets = secrets
  end

  private

  attr_reader :organization, :configurations, :secrets

  def feature_flag_name
    :private_registry_config_ui
  end

  def feature_flag_url
    "https://devportal.githubapp.com/feature-flags/#{feature_flag_name}/overview"
  end

  def enterprise?
    organization.business.present?
  end

  def can_use_org_secrets?
    organization.can_use_org_secrets?
  end

  def can_use_secrets_for_private_repos?
    organization.plan.supports?(:private_secrets_and_variables)
  end

  def can_use_private_registries?
    organization.feature_enabled?(feature_flag_name)
  end

  memoize def configuration_rows
    configurations.map do |config|
      secret = secrets_by_name[config.secret_name]
      row = {
        missing_secret: secret.nil?,
        configuration_id: config.id,
        secret_name: config.secret_name,
        registry_type: config.registry_type,
        url: config.url,
        created_at: config.created_at.utc.to_datetime,
        updated_at: config.updated_at.utc.to_datetime,
        secret_created_at: secret ? Secrets.secret_created_at(secret) : nil,
        secret_updated_at: secret ? Secrets.secret_updated_at(secret) : nil,
        secret_visibility: secret ? describe_secret_visibility(secret) : nil,
      }

      if config.authenticates_with_username_and_password?
        row[:username] = config.username
      end

      row
    end
  end

  memoize def orphaned_secret_rows
    orphaned_secret_names = secrets_by_name.keys - configurations_by_name.keys
    secrets_by_name.slice(*orphaned_secret_names).values.map do |secret|
      {
        name: secret.name,
        created_at: Secrets.secret_created_at(secret),
        updated_at: Secrets.secret_updated_at(secret),
        visibility: describe_secret_visibility(secret),
      }
    end
  end

  memoize def configurations_by_name
    configurations.each_with_object({}) { |config, acc| acc[config.secret_name] = config }
  end

  memoize def secrets_by_name
    secrets.each_with_object({}) { |secret, acc| acc[secret.name] = secret }
  end

  def describe_secret_visibility(secret)
    case secret.visibility
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_ALL_REPOS
      can_use_secrets_for_private_repos? ? "all repositories" : "public repositories"
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_PRIVATE_REPOS
      enterprise? ? "private and internal repositories" : "private repositories"
    when GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS
      "#{secret.selected_repositories_count} #{"repository".pluralize(secret.selected_repositories_count)}"
    end
  end
end
