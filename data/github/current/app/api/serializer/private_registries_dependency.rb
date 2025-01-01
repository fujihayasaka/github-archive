# typed: true
# frozen_string_literal: true

module Api::Serializer::PrivateRegistriesDependency
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  def org_private_registries_hash(data, options = {})
    return { total_count: 0, configurations: [] } unless data[:secrets] || data[:config_data]

    configurations = data[:secrets].map do |secret|
      org_private_registry_hash({
        secret:,
        config_data: data[:config_data][secret.name],
      }, options.merge(exclude: "selected_repository_ids"))
    end.compact

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
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1]
      end

      registry_hash[:selected_repository_ids] = selected_repository_ids
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
      created_at: time(created_at),
      updated_at: time(updated_at),
    }
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
