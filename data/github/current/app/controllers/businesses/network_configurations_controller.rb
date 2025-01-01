# typed: true
# frozen_string_literal: true

class Businesses::NetworkConfigurationsController < Businesses::BusinessController
  require "network_bundle/network_configuration_client"
  include ApplicationController::VerifiedFetchDependency
  include ReactHelper
  include BundleHelper
  include TagAttributeHelper
  include NetworkBundle
  include NetworkConfigurationsHelper
  include Actions::RunnerGroupsHelper
  include Instrumentation::Model

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  allow_verified_fetch only: [:validate_private_network, :remove, :update]

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Mysql5,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Repositories,
  ApplicationRecord::Configurations,
  ApplicationRecord::Copilot,
  ApplicationRecord::Billing,
  only: [:index, :show]

  def index
    payload = generate_payload
    begin
      network_configurations = network_config_client.list_configurations(this_business)
      payload[:networks] = network_configurations.map(&method(:network_config_to_payload))
      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Hosted compute networking",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:networks] = []
      payload[:error] = "Error fetching network configurations"
      GitHub.logger.error({
        msg: "failed to fetch network configurations",
        fn: "network_configurations_controller.index",
        enterprise_id: this_business.id,
        exception: e })
      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Hosted compute networking",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    end
  end

  def new_private_network # rubocop:todo GitHub/UseRestfulActions
    payload = generate_payload
    render_react_app(
      payload: payload,
      layout: "react_business",
      title: "New Private Network",
      page_data: {
        selected_link: :network_configurations
      },
      ssr: true
    )
  end

  def validate_private_network # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    network_settings_id = body["networkSettingsId"].to_s
    begin
      network = network_config_client.get_settings(this_business, network_settings_id)
      render json: {
        privateNetwork: network_settings_to_payload(network)
      }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to validate private network",
        fn: "network_configurations_controller.validate_private_network",
        enterprise_id: this_business.id,
        network_settings_id: network_settings_id,
        exception: e })
      render json: {
        error: {
          message: e.message,
          code: e.code,
        }
      }, status: :unprocessable_entity
    end
  end

  def show
    payload = generate_payload
    begin
      network_configuration_id = params[:network_configuration_id].to_s
      network_config = network_config_client.get_configuration(this_business, network_configuration_id)
      payload[:privateNetworks] = network_config.network_setting_references.map do |setting_ref|
        network = network_config_client.get_settings(this_business, setting_ref.id)
        network_settings_to_payload(network)
      end

      network_config.runner_groups = network_config.runner_groups
        .map { |runner_group_payload| [runner_group_payload,  runner_group_for(this_business, id: runner_group_payload["id"].to_i)] }
        .select { |_, runner_group| runner_group.present? }
        .each do |runner_group_payload, runner_group|
          runner_group_payload["name"] = runner_group.name.to_s
          runner_group_payload["allowPublic"] = runner_group.allow_public
          runner_group_payload["visibility"] = Actions::RunnerGroup.visibility_for(runner_group, this_business).capitalize
          runner_group_payload["selectedTargetsCount"] = runner_group.selected_targets.count
        end
        .map { |runner_group_payload, _| runner_group_payload }
      payload[:networkConfiguration] = network_config_to_payload(network_config)

      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Manage Network Configuration",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:error] = "Error fetching network configuration"
      GitHub.logger.error({
        msg: "failed to show network configuration",
        fn: "network_configurations_controller.show",
        enterprise_id: this_business.id,
        network_id: params[:network_configuration_id],
        exception: e })
      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Manage Network Configuration",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    end
  end

  def remove # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    network_configuration_id = body["configurationId"].to_s

    begin
      network_config = network_config_client.get_configuration(this_business, network_configuration_id)

      network_config.network_setting_references.each do |setting_ref|
        network_config_client.deregister_settings(this_business, setting_ref.id)
      end

      if network_config.compute_service == NetworkBundle::ComputeService::Codespaces
        Codespaces::NetworkConfiguration.new(
          id: network_config.id,
          name: network_config.name,
          enterprise: this_business,
        ).refresh_cache!
      end

      instrument :delete, { network_configuration_id: network_configuration_id }
      network_config_client.delete_configuration(this_business, network_configuration_id)
      render json: {}, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to remove network configuration",
        fn: "network_configurations_controller.remove",
        enterprise_id: this_business.id,
        network_configuration_id: network_configuration_id,
        exception: e })
      render json: {
        error: {
          message: e.message,
          code: e.code,
        }
      }, status: :unprocessable_entity
    end
  end

  def edit
    payload = generate_payload
    begin
      network_configuration_id = params[:network_configuration_id].to_s
      network_config = network_config_client.get_configuration(this_business, network_configuration_id)
      payload[:networkConfiguration] = network_config_to_payload(network_config)
      payload[:privateNetworks] = network_config.network_setting_references.map do |setting_ref|
        network = network_config_client.get_settings(this_business, setting_ref.id)
        network_settings_to_payload(network)
      end

      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Edit Network Configuration",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:error] = "Error fetching network configuration"
      GitHub.logger.error({
        msg: "failed to show network configuration",
        fn: "network_configurations_controller.show",
        enterprise_id: this_business.id,
        network_id: network_configuration_id,
        exception: e })
      render_react_app(
        payload: payload,
        layout: "react_business",
        title: "Edit Network Configuration",
        page_data: {
          selected_link: :network_configurations
        },
        ssr: true
      )
    end
  end

  # This will include create, update, disable, enable
  # create: send name, settings_id, compute_service
  # update: name?, settings_id?, compute_service = true, configuration_id
  # disable: configuration_id, compute_service = 'none'
  # enable: configuration_id, compute_service
  def update
    body = JSON.parse(request&.body.read)

    selected_service = NetworkBundle::ComputeService.deserialize(body.fetch("computeService"))
    network_configuration_id = body["configurationId"].to_s
    name = body["name"].to_s
    requested_settings_ids = body.fetch("privateNetworkIds") { body.key?("networkSettingsId") ? [body["networkSettingsId"]] : [] }

    if network_configuration_id.present?
      network_config = network_config_client.get_configuration(this_business, network_configuration_id)
      persisted_settings_ids = network_config.network_setting_references.map(&:id)
      if !body.key?("privateNetworkIds") && !body.key?("networkSettingsId")
        requested_settings_ids = persisted_settings_ids
      end
    else
      persisted_settings_ids = []
    end

    removed_ids = persisted_settings_ids - requested_settings_ids
    added_ids = requested_settings_ids - persisted_settings_ids

    begin
      if requested_settings_ids.count > 1
        if selected_service == ComputeService::Codespaces
          regions = requested_settings_ids.map do |id|
            network_config_client.get_settings(this_business, id).location
          end

          location, count = regions.tally.find { |_, v| v > 1 }
          if location.present?
            render json: {
              error: {
                message: "There is already a network registered in the region '#{location}'",
                code: "DuplicateLocation",
              }
            }, status: :unprocessable_entity
            return
          end
        else
          render json: {
            error: {
              message: "The network configuration cannot have more than one network resource",
              code: "InvalidOperation",
            }
          }, status: :unprocessable_entity
          return
        end
      end

      removed_ids.each do |id|
        network_config_client.deregister_settings(this_business, id)
      end

      added_ids.each do |id|
        network_config_client.register_settings(this_business, id)
      end

      network = network_config_client.create_or_update_configuration(
        this_business,
        configuration_id: network_configuration_id,
        network_setting_ids: requested_settings_ids,
        name: name,
        selected_service: selected_service,
      )

      # If there wasn't a network_configuration_id, then we created a new network configuration
      # either way, we have one to report
      instrument network_configuration_id.present? ? :update : :create, {
        network_configuration_id: network.id,
        name: network.name,
        selected_service: selected_service.serialize,
        network_settings_ids: requested_settings_ids,
        previous_settings_ids: removed_ids,
      }

      if selected_service == ComputeService::Codespaces
        ensure_codespaces_compute_resource(network)
        Codespaces::NetworkConfiguration.new(
          id: network.id,
          name: network.name,
          enterprise: this_business,
        ).refresh_cache!
      end

      render json: {}, status: :created, location: show_settings_network_configurations_path(this_business, network.id)
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to update network configuration",
        fn: "network_configurations_controller.update",
        enterprise_id: this_business.id,
        network_configuration_name: name,
        network_configuration_id: network_configuration_id,
        network_settings_id: requested_settings_ids,
        selected_service: selected_service.serialize,
        exception: e })
      render json: {
        error: {
          message: e.message,
          code: e.code,
        }
      }, status: :unprocessable_entity
    end
  end

  # Finds a network configuration
  def find # rubocop:todo GitHub/UseRestfulActions
    name = params.require(:name)
    begin
      # Find any network configuration by name
      network_configurations = network_config_client.list_configurations(this_business, "", "", nil, name)
      render json: {
        networkConfigurations: network_configurations.map(&method(:network_config_to_payload))
      }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed when finding network configurations",
        fn: "network_configurations_controller.find",
        enterprise_id: this_business.id,
        network_configuration_name: name,
        exception: e })
      render json: {
        error: {
          message: e.message,
          code: e.code,
        }
      }, status: :bad_request
    end
  end

  private

  # A compute resource is required to query for the actual network settings
  # (regions, subnet IDs, etc.) and codespaces doesn't have anything that fits
  # well with the concept of compute resource here (Actions has runner groups,
  # but codespaces doesn't expose the concept of pools to users), so when a
  # network configuration allows codespaces, we need to setup a dummy compute
  # resource that has the same ID as the network configuration so we can query
  # for network settings for a given network configuration ID.
  sig { params(configuration: NetworkBundle::NetworkConfiguration).void }
  def ensure_codespaces_compute_resource(configuration)
    if configuration.compute_service == NetworkBundle::ComputeService::Codespaces
      resources = T.cast(configuration.compute_resources.find { |s| s.fetch("name") == "codespaces" }&.dig("resources") || [], Array)
      unless resources.any? { |cr| cr["id"] == configuration.id }
        retry_count = 0
        begin
          network_config_client.configure_compute_resource(this_business, configuration.id, "codespaces", configuration.id, "codespaces-compute-resource")
        rescue NetworkBundle::NetworkConfigurationsException => e
          GitHub.logger.error(
            "Failed to add codespaces compute resource",
            "code.function" => "network_configurations_controller.ensure_codespaces_compute_resource",
            "gh.business.id" => this_business.id,
            "gh.hosted_compute_networking.network_id" => configuration.id,
            "gh.hosted_compute_networking.network_name" => configuration.name,
            "exception.message" => e.message,
            "gh.hosted_compute_networking.retry_count" => retry_count,
          )
          retry if (retry_count += 1) < 3
        end
      end
    end
  end

  def generate_payload
    {
      networkConfigurationsPath: settings_network_configurations_path(this_business),
      removeNetworkConfigurationPath: remove_settings_network_configurations_path(this_business),
      newPrivateNetworkPath: new_private_network_settings_network_configurations_path(this_business),
      findNetworkConfigurationPath: find_settings_network_configurations_path(this_business),
      updateNetworkConfigurationPath: update_settings_network_configurations_path(this_business),
      runnerGroupPath: settings_actions_runner_groups_enterprise_path(this_business),
      enabledForCodespaces: enabled_for_codespaces?,
      displayConfigStatusBanner: display_config_status_banner?,
      displayAllVNetStatusBanner: display_all_status_banner?,
      isBusiness: true,
      orgCanEditNetworkConfiguration: true,
      userCanEditNetworkConfiguration: true
    }
  end

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
      business: this_business
    }
  end

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end

  def enabled_for_codespaces?
    this_business.in_codespaces_salus_beta? && this_business.feature_enabled?(:codespaces_vnet_injection_beta)
  end

  def display_config_status_banner?
    this_business.feature_enabled?(:runners_vnet_display_config_status_banner)
  end

  def display_all_status_banner?
    this_business.feature_enabled?(:runners_vnet_display_all_status_banner)
  end
end
