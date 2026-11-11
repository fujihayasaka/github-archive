# typed: true
# frozen_string_literal: true

module Api::Serializer::NetworkConfigurationsDependency
  sig { params(data: { network_configurations: T::Array[NetworkBundle::NetworkConfiguration] }, options: T.untyped).returns(Hash) }
  def network_configurations_hash(data, options = {})
    configs = data.fetch(:network_configurations, [])
    {
      total_count: configs.length,
      network_configurations: configs.map do |p|
        network_configuration_hash({ network_configuration: p })
      end
    }
  end

  sig { params(data: { network_configuration: NetworkBundle::NetworkConfiguration }, options: T.untyped).returns(Hash) }
  def network_configuration_hash(data, options = {})
    network_configuration = data[:network_configuration]
    {
      id: network_configuration.id,
      name: network_configuration.name,
      compute_service: network_configuration.compute_service,
      network_settings_ids: network_configuration.network_setting_references.map(&:id),
      created_on: network_configuration.created_on.to_time.utc,
    }
  end

  sig { params(data: { network_settings: NetworkBundle::NetworkSettings }, options: T.untyped).returns(Hash) }
  def network_settings_hash(data, options = {})
    network_settings = data[:network_settings]
    {
      id: network_settings.id,
      name: network_settings.resource_name,
      network_configuration_id: network_settings.network_configuration_id,
      subnet_id: network_settings.subnet_id,
      region: network_settings.location,
    }
  end
end
