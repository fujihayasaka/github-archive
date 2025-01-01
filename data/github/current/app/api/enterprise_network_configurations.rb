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

    deliver :network_configurations_hash, { network_configurations: network_configurations }
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

    deliver :network_configuration_hash, { network_configuration: network_configuration }
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
    name = data["name"]
    network_settings_ids = data["network_settings_ids"]
    compute_service = data["compute_service"]

    network_configuration = handle_network_client_errors! do
      network_settings_ids.each do |id|
        network_config_client.register_settings(enterprise, id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{id} does not exist."
      end
      network_config_client.create_or_update_configuration(enterprise, name: name, network_setting_ids: network_settings_ids, selected_service: compute_service)
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
      post = network_config_client.create_or_update_configuration(
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
    when "DisplayNameInUse", "NetworkResourceInUse", "InvalidConfigurationId", "InvalidDisplayName", "InvalidResourcePayload"
      # The built-in message is fine for these errors
      deliver_error! 422, message: e.message
    when "InvalidBusinessId"
      deliver_error! 422, message: "The business ID is invalid or does not match the configuration's."
    else
      Failbot.report!(e)
      deliver_error! 500, message: "Internal server error."
    end
  end
end
