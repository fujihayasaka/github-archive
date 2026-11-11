# typed: true
# frozen_string_literal: true

module Api::Serializer::PrivateRegistriesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def org_private_registries_hash(data, options = {})
    return { total_count: 0, configurations: [] } unless data[:secrets] || data[:config_data]

    configurations = Array(data[:secrets]).filter_map do |secret|
      config = data[:config_data][secret.name]
      next nil unless config

      org_private_registry_hash({ secret:, config_data: config }, options.merge(exclude: "selected_repository_ids"))
    end

    { total_count: data[:total_count], configurations: }
  end

  def org_private_registry_hash(data, options = {})
    return nil unless data[:secret] && data[:config_data]

    secret = data[:secret]
    config = data[:config_data]

    return nil unless secret.name == config.secret_name

    registry_hash = private_registry_hash(data, options)
    registry_hash[:visibility] = GitHub::KredzClient::Credz::TO_VISIBILITY_MAP[secret.visibility]

    if (
      secret.visibility == GitHub::KredzClient::Credz::CREDENTIAL_VISIBILITY_SELECTED_REPOS &&
      !coerce_array(options[:exclude]).include?("selected_repository_ids")
    )
      selected_repository_global_ids = secret.selected_repositories.map(&:global_id)
      selected_repository_ids = selected_repository_global_ids.map do |global_id|
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1].to_i
      end

      registry_hash[:selected_repository_ids] = selected_repository_ids
    end

    return registry_hash unless config.oidc?

    case config.auth_type
    when "oidc_azure"
      registry_hash[:tenant_id] = config.tenant_id
      registry_hash[:client_id] = config.client_id
    when "oidc_aws"
      registry_hash[:aws_region] = config.aws_region
      registry_hash[:account_id] = config.account_id
      registry_hash[:role_name] = config.role_name
      registry_hash[:domain] = config.domain
      registry_hash[:domain_owner] = config.domain_owner
      registry_hash[:audience] = config.audience if config.audience.present?
    when "oidc_jfrog"
      registry_hash[:jfrog_oidc_provider_name] = config.jfrog_oidc_provider_name
      registry_hash[:audience] = config.audience if config.audience.present?
      registry_hash[:identity_mapping_name] = config.identity_mapping_name if config.identity_mapping_name.present?
    when "oidc_cloudsmith"
      registry_hash[:namespace] = config.namespace
      registry_hash[:service_slug] = config.service_slug
      registry_hash[:audience] = config.audience
      registry_hash[:api_host] = config.api_host if config.api_host.present?
    when "oidc_gcp"
      registry_hash[:workload_identity_provider] = config.workload_identity_provider
      registry_hash[:service_account] = config.service_account if config.service_account.present?
      registry_hash[:audience] = config.audience if config.audience.present?
    end

    registry_hash
  end

  def private_registry_hash(data, options = {})
    return nil unless data[:secret] && data[:config_data]

    secret = data[:secret]
    config = data[:config_data]

    return nil unless secret.name == config.secret_name

    created_at = config.created_at
    # Updated should be the more recent of the config or secret updated at
    updated_at = secret.updated_at.nil? ? created_at : Time.at(secret.updated_at&.seconds)
    updated_at = config.updated_at.after?(updated_at) ? config.updated_at : updated_at

    registry_hash = {
      name: config.secret_name,
      registry_type: config.registry_type,
      url: config.url,
      replaces_base: config.replaces_base || false,
      created_at: time(created_at),
      updated_at: time(updated_at),
    }
    registry_hash[:auth_type] = config.auth_type
    registry_hash[:username] = config.username if config.username

    registry_hash
  end

  private

  def coerce_array(obj)
    if obj.is_a?(String)
      obj.split(",")
    else
      Array.wrap(obj)
    end
  end
end
