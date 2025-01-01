# typed: true
# frozen_string_literal: true

class Api::OrganizationNetworkConfigurations < Api::App
  include NetworkConfigurationsHelper
  include ReceiveSchemaWithOpenApi

  FORBIDDEN_MESSAGE = "You must be an org admin or have the network configurations fine-grained permission."

  # Get all network configurations
  get "/organizations/:organization_id/settings/network-configurations", operation_id: "hosted-compute/list-network-configurations-for-org" do
    org = find_org!

    validate_read_usage!(org)

    control_access :read_org_network_configurations,
      resource: org,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    # List the configs
    network_configurations = handle_network_client_errors! do
      network_config_client.list_configurations(org)
    end

    GitHub.logger.info({
      msg: "Listing network configurations for org, found #{network_configurations&.length} configurations",
      "code.namespace": self.class.name,
      "code.function": __method__,
    })

    # Handle pagination
    network_configurations = paginate_rel(network_configurations)

    deliver :network_configurations_hash, { network_configurations: network_configurations }
  end

  # Get an individual network configuration
  get "/organizations/:organization_id/settings/network-configurations/:network_configuration_id", operation_id: "hosted-compute/get-network-configuration-for-org" do
    org = find_org!

    validate_read_usage!(org)

    control_access :read_org_network_configurations,
      resource: org,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    network_configuration = handle_network_client_errors! do
      network_config_client.get_configuration(org, params[:network_configuration_id])
    end

    deliver :network_configuration_hash, { network_configuration: network_configuration }
  end

  # Create an individual network configuration
  post "/organizations/:organization_id/settings/network-configurations", operation_id: "hosted-compute/create-network-configuration-for-org" do
    org = find_org!

    validate_write_usage!(org)

    control_access :write_org_network_configurations,
      resource: org,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    name = data["name"]
    network_settings_ids = data["network_settings_ids"]
    compute_service = data["compute_service"]

    network_configuration = handle_network_client_errors! do
      network_settings_ids.each do |id|
        network_config_client.register_settings(org, id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{id} does not exist."
      end
      network_config_client.create_or_update_configuration(org, name: name, network_setting_ids: network_settings_ids, selected_service: compute_service)
    end

    deliver :network_configuration_hash, { network_configuration: network_configuration }, status: 201
  end

  # Update an individual network configuration
  patch "/organizations/:organization_id/settings/network-configurations/:network_configuration_id", operation_id: "hosted-compute/update-network-configuration-for-org" do
    org = find_org!

    validate_write_usage!(org)

    control_access :write_org_network_configurations,
      resource: org,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    data = receive_with_openapi
    name = data["name"].to_s
    requested_settings_ids = data["network_settings_ids"] || []
    compute_service_raw = data["compute_service"]
    if compute_service_raw.present?
      compute_service = NetworkBundle::ComputeService.deserialize(compute_service_raw)
    end

    # FUTURE: when supporting multiple network settings, we'll likely need to check their regions to avoid duplicates

    network_configuration = handle_network_client_errors! do
      pre = network_config_client.get_configuration(org, params[:network_configuration_id])
      persisted_settings_ids = pre.network_setting_references.map(&:id)
      if requested_settings_ids.present?
        # deregister old settings, and register the new
        removed_ids = persisted_settings_ids - requested_settings_ids
        added_ids = requested_settings_ids - persisted_settings_ids

        added_ids.each do |id|
          begin
            network_config_client.register_settings(org, id)
          rescue NetworkBundle::NetworkConfigurationsException => e
            raise if e.code != "NotFound"
            deliver_error! 422, message: "Network settings with ID #{id} does not exist."
          end
        end

        removed_ids.each do |id|
          begin
            network_config_client.deregister_settings(org, id)
          rescue NetworkBundle::NetworkConfigurationsException => e
            raise if e.code != "NotFound"
            deliver_error! 422, message: "Network settings with ID #{id} does not exist."
          end
        end
      else
        requested_settings_ids = persisted_settings_ids
      end

      # Update
      network_config_client.create_or_update_configuration(
        org,
        configuration_id: params[:network_configuration_id],
        network_setting_ids: requested_settings_ids,
        name: name,
        selected_service: compute_service,
      )
    end

    deliver :network_configuration_hash, { network_configuration: network_configuration }, status: 200
  end

  # Delete an individual network configuration
  delete "/organizations/:organization_id/settings/network-configurations/:network_configuration_id", operation_id: "hosted-compute/delete-network-configuration-from-org" do
    org = find_org!

    validate_write_usage!(org)

    control_access :write_org_network_configurations,
      resource: org,
      forbid: true,
      forbid_message: FORBIDDEN_MESSAGE,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    handle_network_client_errors! do
      network_configuration = network_config_client.get_configuration(org, params[:network_configuration_id])
      network_configuration.network_setting_references.each do |ns|
        network_config_client.deregister_settings(org, ns.id)
      rescue NetworkBundle::NetworkConfigurationsException => e
        raise if e.code != "NotFound"
        deliver_error! 422, message: "Network settings with ID #{ns.id} does not exist."
      end
      network_config_client.delete_configuration(org, params[:network_configuration_id])
    end

    deliver_empty status: 204
  end

  private

  def validate_read_usage!(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_network_configuration_api)
    deliver_error! 404 unless plan_allows_network_configurations?(org)
    deliver_error! 404 unless can_view_network_configuration?(org)
  end

  def validate_write_usage!(org)
    deliver_error! 404 unless org.feature_enabled?(:actions_network_configuration_api)
    deliver_error! 404 unless plan_allows_network_configurations?(org)
    deliver_error! 422, message: "#{edit_prevention_reason(org)}." unless can_edit_network_configuration?(org)
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
