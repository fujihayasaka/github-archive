# typed: true
# frozen_string_literal: true

class Api::EnterpriseNetworkConfigurations < Api::App
  include NetworkConfigurationsHelper
  include ReceiveSchemaWithOpenApi
  include Instrumentation::Model

  # Get all network configurations
  get "/enterprises/:enterprise_id/network-configurations", operation_id: "hosted-compute/list-network-configurations-for-enterprise" do
    enterprise = find_enterprise!

    validate_read_usage!(enterprise)

    control_access :read_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    # List the configs
    network_configurations = handle_network_client_errors! do
      network_config_client.list_configurations(enterprise)
    end

    # Handle pagination
    network_configurations = paginate_rel(network_configurations)

    if failover_feature_enabled?(actor: enterprise)
      deliver :network_configurations_hash_next, { network_configurations: network_configurations }
    else
      deliver :network_configurations_hash, { network_configurations: network_configurations }
    end
  end

  # Get an individual network configuration
  get "/enterprises/:enterprise_id/network-configurations/:network_configuration_id", operation_id: "hosted-compute/get-network-configuration-for-enterprise" do
    enterprise = find_enterprise!

    validate_read_usage!(enterprise)

    control_access :read_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    network_configuration = handle_network_client_errors! do
      network_config_client.get_configuration(enterprise, params[:network_configuration_id])
    end

    if failover_feature_enabled?(actor: enterprise)
      deliver :network_configuration_hash_next, { network_configuration: network_configuration }
    else
      deliver :network_configuration_hash, { network_configuration: network_configuration }
    end
  end

  # Create an individual network configuration
  post "/enterprises/:enterprise_id/network-configurations", operation_id: "hosted-compute/create-network-configuration-for-enterprise" do
    enterprise = find_enterprise!

    validate_write_usage!(enterprise)

    control_access :write_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi

    if failover_feature_enabled?(actor: enterprise)
      post_next(enterprise: enterprise, data: data)
    else
      post_legacy(enterprise: enterprise, data: data)
    end
  end

  def post_next(enterprise:, data:) # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
    compute_service_raw = data["compute_service"]
    if compute_service_raw.present?
      compute_service = NetworkBundle::ComputeService.deserialize(compute_service_raw)
    end

    network_settings_ids = data["network_settings_ids"] || []
    failover_network_settings_ids = data["failover_network_settings_ids"] || []
    failover_network_enabled = data["failover_network_enabled"] || false

    network_configuration = handle_network_client_errors! do
      # Validate that all provided network settings exist for backward compatibility
      (network_settings_ids + failover_network_settings_ids).each do |id|
        network_config_client.get_settings(enterprise, id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{id} does not exist."
      end

      # Create
      network_config_client.create_or_update_configuration(
        enterprise,
        name: data["name"],
        network_setting_ids: network_settings_ids,
        failover_network_setting_ids: failover_network_settings_ids,
        failover_network_enabled: failover_network_enabled,
        selected_service: compute_service
      )
    end

    instrument :create, {
      network_configuration_id: network_configuration.id,
      name: network_configuration.name,
      selected_service: network_configuration.compute_service.serialize,
      network_settings_ids: network_settings_ids,
      failover_network_settings_ids: failover_network_settings_ids,
      failover_network_enabled: failover_network_enabled
    }

    deliver :network_configuration_hash_next, { network_configuration: network_configuration }, status: 201
  end

  def post_legacy(enterprise:, data:) # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
    name = data["name"]
    network_settings_ids = data["network_settings_ids"]
    compute_service_raw = data["compute_service"]
    if compute_service_raw.present?
      compute_service = NetworkBundle::ComputeService.deserialize(compute_service_raw)
    end

    network_configuration = handle_network_client_errors! do
      network_settings_ids.each do |id|
        network_config_client.register_settings(enterprise, id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{id} does not exist."
      end
      network_config_client.create_or_update_configuration_legacy(enterprise, name: name, network_setting_ids: network_settings_ids, selected_service: compute_service)
    end

    instrument :create, {
      network_configuration_id: network_configuration.id,
      name: network_configuration.name,
      selected_service: network_configuration.compute_service.serialize,
      network_settings_ids: network_settings_ids
    }

    deliver :network_configuration_hash, { network_configuration: network_configuration }, status: 201
  end

  # Update an individual network configuration
  patch "/enterprises/:enterprise_id/network-configurations/:network_configuration_id", operation_id: "hosted-compute/update-network-configuration-for-enterprise" do
    enterprise = find_enterprise!

    validate_write_usage!(enterprise)

    control_access :write_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    data = receive_with_openapi

    if failover_feature_enabled?(actor: enterprise)
      patch_next(enterprise: enterprise, data: data)
    else
      patch_legacy(enterprise: enterprise, data: data)
    end
  end

  def patch_next(enterprise:, data:) # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
    compute_service_raw = data["compute_service"]
    if compute_service_raw.present?
      compute_service = NetworkBundle::ComputeService.deserialize(compute_service_raw)
    end

    network_settings_ids = T.let(data["network_settings_ids"], T.nilable(T::Array[String]))
    failover_network_settings_ids = T.let(data["failover_network_settings_ids"], T.nilable(T::Array[String]))
    failover_network_enabled = T.let(data["failover_network_enabled"], T.nilable(T::Boolean))

    network_configuration = handle_network_client_errors! do
      # get network configuration to backfill missing fields required by the client (and for backward compatibility)
      existing_configuration = network_config_client.get_configuration(enterprise, params[:network_configuration_id])

      if !network_settings_ids.present? # the primary network must always be present
        network_settings_ids = existing_configuration.network_setting_references.reject { |r| r.isFailover }.map(&:id)
      end

      if failover_network_settings_ids.nil? # an empty array means "no failover", nil means "keep existing"
        failover_network_settings_ids = existing_configuration.network_setting_references.select { |r| r.isFailover }.map(&:id)
      end

      if failover_network_enabled.nil?
        failover_network_enabled = existing_configuration.network_setting_references.any? { |r| r.isFailover && r.enabled }
      end

      # Validate that all provided network settings exist for backward compatibility
      (Array(data["network_settings_ids"]) + Array(data["failover_network_settings_ids"])).each do |id|
        network_config_client.get_settings(enterprise, id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{id} does not exist."
      end

      # Update
      network_config_client.create_or_update_configuration(
        enterprise,
        configuration_id: params[:network_configuration_id],
        name: data["name"],
        network_setting_ids: network_settings_ids,
        failover_network_setting_ids: failover_network_settings_ids,
        failover_network_enabled: failover_network_enabled,
        selected_service: compute_service,
      )
    end

    instrument :update, {
      network_configuration_id: network_configuration.id,
      name: network_configuration.name,
      selected_service: network_configuration.compute_service.serialize,
      network_settings_ids: network_settings_ids,
      failover_network_settings_ids: failover_network_settings_ids,
      failover_network_enabled: failover_network_enabled
    }

    deliver :network_configuration_hash_next, { network_configuration: network_configuration }, status: 200
  end

  def patch_legacy(enterprise:, data:) # rubocop:disable GitHub/ApiMethodsCallingDeliverBangMustHaveBangs
    name = data["name"].to_s
    requested_settings_ids = data["network_settings_ids"] || []
    compute_service_raw = data["compute_service"]
    if compute_service_raw.present?
      compute_service = NetworkBundle::ComputeService.deserialize(compute_service_raw)
    end

    # FUTURE: when supporting multiple network settings, we'll likely need to check their regions to avoid duplicates

    network_configuration = handle_network_client_errors! do
      pre = network_config_client.get_configuration(enterprise, params[:network_configuration_id])
      persisted_settings_ids = pre.network_setting_references.map(&:id)
      if requested_settings_ids.present?
        # deregister old settings, and register the new
        removed_ids = persisted_settings_ids - requested_settings_ids
        added_ids = requested_settings_ids - persisted_settings_ids

        added_ids.each do |id|
          begin
            network_config_client.register_settings(enterprise, id)
          rescue NetworkBundle::NetworkConfigurationsException => e
            raise if e.code != "NotFound"
            deliver_error! 422, message: "Network settings with ID #{id} does not exist."
          end
        end

        removed_ids.each do |id|
          begin
            network_config_client.deregister_settings(enterprise, id)
          rescue NetworkBundle::NetworkConfigurationsException => e
            raise if e.code != "NotFound"
            deliver_error! 422, message: "Network settings with ID #{id} does not exist."
          end
        end
      else
        requested_settings_ids = persisted_settings_ids
      end

      # Update
      post = network_config_client.create_or_update_configuration_legacy(
        enterprise,
        configuration_id: params[:network_configuration_id],
        network_setting_ids: requested_settings_ids,
        name: name,
        selected_service: compute_service,
      )

      instrument :update, {
          network_configuration_id: post.id,
          name: post.name,
          selected_service: post.compute_service.serialize,
          network_settings_ids: post.network_setting_references.map(&:id),
          previous_settings_ids: persisted_settings_ids
      }

      post
    end

    deliver :network_configuration_hash, { network_configuration: network_configuration }, status: 200
  end

  # Delete an individual network configuration
  delete "/enterprises/:enterprise_id/network-configurations/:network_configuration_id", operation_id: "hosted-compute/delete-network-configuration-from-enterprise" do
    enterprise = find_enterprise!

    validate_write_usage!(enterprise)

    control_access :write_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    network_configuration_id = params[:network_configuration_id]

    if failover_feature_enabled?(actor: enterprise)
      handle_network_client_errors! do
        network_config_client.delete_configuration(enterprise, network_configuration_id)
      end
    else
      handle_network_client_errors! do
        network_configuration = network_config_client.get_configuration(enterprise, network_configuration_id)
        network_configuration.network_setting_references.each do |ns|
          network_config_client.deregister_settings(enterprise, ns.id)
        rescue NetworkBundle::NetworkConfigurationsException => e
          raise if e.code != "NotFound"
          deliver_error! 422, message: "Network settings with ID #{ns.id} does not exist."
        end
        network_config_client.delete_configuration(enterprise, network_configuration_id)
      end
    end

    instrument :delete, {
      network_configuration_id: network_configuration_id,
    }

    deliver_empty status: 204
  end

  # Get an individual network settings
  get "/enterprises/:enterprise_id/network-settings/:network_settings_id", operation_id: "hosted-compute/get-network-settings-for-enterprise" do
    enterprise = find_enterprise!

    validate_read_usage!(enterprise)

    control_access :read_enterprise_network_configurations,
      resource: enterprise,
      forbid: true,
      allow_integrations: false,
      allow_user_via_granular_actor: false,
      enforce_oauth_app_policy: false

    network_settings = handle_network_client_errors! do
      network_config_client.get_settings(enterprise, params[:network_settings_id])
    end

    deliver :network_settings_hash, { network_settings: network_settings }
  end

  private

  # Default action prefix for audit log events
  sig { returns(String) }
  def event_prefix
    "network_configuration"
  end

  # Default payload values for audit log events
  sig { returns(Hash) }
  def event_payload
    {
      actor: current_user,
      business: find_enterprise!
    }
  end

  def validate_read_usage!(enterprise)
    deliver_error! 404 unless plan_allows_network_configurations?(enterprise)
    deliver_error! 404 unless can_view_network_configuration?(enterprise)
  end

  def validate_write_usage!(enterprise)
    deliver_error! 404 unless plan_allows_network_configurations?(enterprise)
    deliver_error! 422, message: "#{edit_prevention_reason(enterprise)}." unless can_edit_network_configuration?(enterprise)
  end

  def handle_network_client_errors!
    yield
  rescue NetworkBundle::NetworkConfigurationsException => e
    # Error codes come from the network service, see here:
    #   https://github.com/github/cps-network-service/blob/main/src/service/Exceptions/ServiceOperationResultCode.cs
    case e.code
    when "NotFound"
      deliver_error! 404
    when "Failed", "Unknown"
      Failbot.report!(e)
      deliver_error! 500, message: "Internal server error."
    when "InvalidBusinessId"
      deliver_error! 422, message: "The business ID is invalid or does not match the configuration's."
    else
      # The built-in message is fine for these errors
      deliver_error! 422, message: e.message
    end
  end
end
