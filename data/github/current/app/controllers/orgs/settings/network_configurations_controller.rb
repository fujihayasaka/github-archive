# typed: true
# frozen_string_literal: true

class Orgs::Settings::NetworkConfigurationsController < Orgs::Controller
  require "network_bundle/network_configuration_client"
  include ApplicationController::VerifiedFetchDependency
  include ApplicationController::JsonDependency
  include NetworkBundle
  include NetworkConfigurationsHelper
  include Actions::RunnerGroupsHelper
  include Instrumentation::Model

  before_action :login_required
  before_action :check_private_networking_enabled
  before_action :ensure_user_has_network_configurations_read_access, only: [:index, :find, :show, :validate_private_network]
  before_action :ensure_user_has_network_configurations_write_access, only: [:edit, :update, :remove, :new_private_network]
  allow_verified_fetch only: [:validate_private_network, :remove, :update]

  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations"
  end

  layout "organization_settings"

  stylesheet_bundle :settings
  javascript_bundle :settings

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
      network_configurations = network_config_client.list_configurations(this_organization)
      payload[:networks] = network_configurations.map(&method(:network_config_to_payload))
      render_react_app(
        payload: payload,
        title: "Hosted compute networking",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings,
        },
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:networks] = []
      payload[:error] = "Error fetching network configurations"
      GitHub.logger.error({
        msg: "failed to fetch network configurations",
        fn: "network_configurations_controller.index",
        org_id: this_organization.id,
        exception: e })
      render_react_app(
        payload: payload,
        title: "Hosted compute networking",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings,
        },
      )
    end
  end

  def new_private_network # rubocop:todo GitHub/UseRestfulActions
    payload = generate_payload
    render_react_app(
      payload: payload,
      title: "New Private Network",
      page_data: {
        selected_link: :network_configurations,
        sidebar: :settings,
      },
    )
  end

  def validate_private_network # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    network_settings_id = body["networkSettingsId"].to_s
    begin
      network = network_config_client.get_settings(this_organization, network_settings_id)
      render json: {
        privateNetwork: network_settings_to_payload(network)
      }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to validate private network",
        fn: "network_configurations_controller.validate_private_network",
        org_id: this_organization.id,
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
      network_config = network_config_client.get_configuration(this_organization, network_configuration_id)
      payload[:privateNetworks] = network_config.network_setting_references.map do |setting_ref|
        network = network_config_client.get_settings(this_organization, setting_ref.id)
        network_settings_to_payload(network)
      end

      network_config.runner_groups = network_config.runner_groups
        .map { |runner_group_payload| [runner_group_payload,  runner_group_for(this_organization, id: runner_group_payload["id"].to_i, is_ui_read: true)] }
        .select { |_, runner_group| runner_group.present? }
        .each do |runner_group_payload, runner_group|
          runner_group_payload["name"] = runner_group.name.to_s
          runner_group_payload["allowPublic"] = runner_group.allow_public
          runner_group_payload["visibility"] = Actions::RunnerGroup.visibility_for(runner_group).capitalize
          runner_group_payload["selectedTargetsCount"] = runner_group.selected_targets.count
        end
        .map { |runner_group_payload, _| runner_group_payload }
      payload[:networkConfiguration] = network_config_to_payload(network_config)

      render_react_app(
        payload: payload,
        title: "Manage Network Configuration",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings,
        },
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:error] = "Error fetching network configuration"
      GitHub.logger.error({
        msg: "failed to show network configuration",
        fn: "network_configurations_controller.show",
        org_id: this_organization.id,
        network_id: params[:network_configuration_id],
        exception: e })
      render_react_app(
        payload: payload,
        title: "Manage Network Configuration",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings,
        },
      )
    end
  end

  def remove # rubocop:todo GitHub/UseRestfulActions
    body = JSON.parse(request&.body.read)
    network_configuration_id = body["configurationId"].to_s
    begin
      network_config = network_config_client.get_configuration(this_organization, network_configuration_id)
      network_config.network_setting_references.each do |setting_ref|
        network_config_client.deregister_settings(this_organization, setting_ref.id)
      end

      if network_config.compute_service == NetworkBundle::ComputeService::Codespaces
        Codespaces::NetworkConfiguration.new(
          id: network_config.id,
          name: network_config.name,
          enterprise: this_organization,
        ).refresh_cache!
      end

      instrument :delete, { network_configuration_id: network_configuration_id }
      network_config_client.delete_configuration(this_organization, network_configuration_id)
      render json: {}, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to remove network configuration",
        fn: "network_configurations_controller.remove",
        org_id: this_organization.id,
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
      network_config = network_config_client.get_configuration(this_organization, network_configuration_id)
      payload[:privateNetworks] = network_config.network_setting_references.map do |setting_ref|
        network = network_config_client.get_settings(this_organization, setting_ref.id)
        network_settings_to_payload(network)
      end

      payload[:networkConfiguration] = network_config_to_payload(network_config)
      render_react_app(
        payload: payload,
        title: "Edit Network Configuration",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings,
        },
      )
    rescue NetworkBundle::NetworkConfigurationsException => e
      payload[:error] = "Error fetching network configuration"
      GitHub.logger.error({
        msg: "failed to show network configuration",
        fn: "network_configurations_controller.show",
        org_id: this_organization.id,
        network_id: network_configuration_id,
        exception: e })
      render_react_app(
        payload: payload,
        title: "Edit Network Configuration",
        page_data: {
          selected_link: :network_configurations,
          sidebar: :settings
        },
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
      network_config = network_config_client.get_configuration(this_organization, network_configuration_id)
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
        if enabled_for_codespaces? && selected_service == ComputeService::Codespaces
          regions = requested_settings_ids.map do |id|
            network_config_client.get_settings(this_organization, id).location
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
        network_config_client.deregister_settings(this_organization, id)
      end

      added_ids.each do |id|
        network_config_client.register_settings(this_organization, id)
      end

      network = network_config_client.create_or_update_configuration(
        this_organization,
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
        Codespaces::NetworkConfiguration.new(
          id: network_config.id,
          name: network_config.name,
          enterprise: this_organization,
        ).refresh_cache!
        ensure_codespaces_compute_resource(network)
      end

      render json: {}, status: :created, location: settings_org_network_configurations_show_path(this_organization, network.id)
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to update network configuration",
        fn: "network_configurations_controller.update",
        org_id: this_organization.id,
        network_configuration_name: name,
        network_configuration_id: network_configuration_id,
        network_settings_ids: requested_settings_ids,
        selected_service: selected_service,
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
      network_configurations = network_config_client.list_configurations(this_organization, "", "", nil, name)
      render json: {
        networkConfigurations: network_configurations.map(&method(:network_config_to_payload))
      }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed when finding network configurations",
        fn: "network_configurations_controller.find",
        enterprise_id: this_organization.id,
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
          network_config_client.configure_compute_resource(this_organization, configuration.id, "codespaces", configuration.id, "codespaces-compute-resource")
        rescue NetworkBundle::NetworkConfigurationsException => e
          GitHub.logger.error(
            "Failed to add codespaces compute resource",
            "code.function" => "network_configurations_controller.ensure_codespaces_compute_resource",
            "gh.org.id" => this_organization.id,
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
      networkConfigurationsPath: settings_org_network_configurations_path(this_organization),
      removeNetworkConfigurationPath: settings_org_network_configurations_remove_path(this_organization),
      newPrivateNetworkPath: settings_org_network_configurations_new_private_network_path(this_organization),
      findNetworkConfigurationPath: settings_org_network_configurations_find_path(this_organization),
      updateNetworkConfigurationPath: settings_org_network_configurations_update_path(this_organization),
      runnerGroupPath: settings_org_actions_runner_groups_path(this_organization),
      enabledForCodespaces: enabled_for_codespaces?,
      displayConfigStatusBanner: display_config_status_banner?,
      displayAllVNetStatusBanner: display_all_status_banner?,
      orgCanEditNetworkConfiguration: can_org_edit_network_configuration?(this_organization),
      userCanEditNetworkConfiguration: current_organization.can_write_organization_network_configurations?(current_user),
      isBusiness: false,
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
      org: this_organization
    }
  end

  def ensure_user_has_network_configurations_read_access
    # Ensure the organization is able to view network configurations
    render_404 unless can_view_network_configuration?(this_organization)
    # Check user permissions within the organization
    render_404 unless this_organization.can_read_organization_network_configurations?(current_user)
  end

  def ensure_user_has_network_configurations_write_access
    # Ensure the organization is able to view network configurations
    render_404 unless can_edit_network_configuration?(this_organization)
    # Check user permissions within the organization
    render_404 unless this_organization.can_write_organization_network_configurations?(current_user)
  end

  def check_private_networking_enabled
    render_404 unless can_view_network_configuration?(this_organization)
  end

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end

  def display_config_status_banner?
    this_organization.feature_flag_enabled?(:runners_vnet_display_config_status_banner, default: false)
  end

  def display_all_status_banner?
    this_organization.feature_flag_enabled?(:runners_vnet_display_all_status_banner, default: false)
  end

  def enabled_for_codespaces?
    false
  end
end
