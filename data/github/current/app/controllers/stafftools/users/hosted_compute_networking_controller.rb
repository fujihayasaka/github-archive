# typed: true
# frozen_string_literal: true

class Stafftools::Users::HostedComputeNetworkingController < StafftoolsController
  include NetworkConfigurationsHelper
  include Actions::RunnerGroupsHelper


  before_action :ensure_user_exists
  before_action :ensure_org_not_user
  before_action :dotcom_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    ApplicationRecord::Configurations,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:show]

  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations"
  end

  def index
    begin
      # Fetch all runner groups for the provided business entity
      all_runner_groups = Actions::RunnerGroup.for_entity(this_user, include_runners: true, include_hosted_runner_groups: true, is_ui_read: true)
      runner_groups = all_runner_groups.filter { |group| !group.hosted? }

      # Fetch network configurations for the current user
      network_configurations = network_config_client.list_configurations(this_user)
      network_configurations.each do |network_config|
        network_config.runner_groups = network_config.runner_groups
          .map do |runner_group_payload|
            # Find the matching runner group from the pre-fetched list
            runner_group = runner_groups.find { |group| group.id == runner_group_payload["id"].to_i }
            [runner_group_payload, runner_group]
          end
          .select { |_, runner_group| runner_group.present? }
          .each do |runner_group_payload, runner_group|
            runner_group_payload["name"] = runner_group.name.to_s
          end
          .map { |runner_group_payload, _| runner_group_payload }
      end
    rescue NetworkBundle::NetworkConfigurationsException => e
      network_configurations = []
      GitHub.logger.error({
        msg: "failed to fetch network configurations",
        fn: "hosted_compute_networking.show",
        organization_id: this_user.id,
        exception: e })
    end
    render_react_app(
      title: "Hosted compute networking",
      payload: {
        networkConfigurations: network_configurations.map(&method(:network_config_to_payload)),
        isEnterprise: false,
        actor: this_user.display_login
      },
      page_data: { selected_link: :hosted_compute_networking },
      layout: "layouts/stafftools/user/content",
    )
  end

  def show
    begin
      network_configuration_id = params[:id].to_s
      network_config = network_config_client.get_configuration(this_user, network_configuration_id)
      private_networks = network_config.network_setting_references.map do |private_network|
        network_config_client.get_settings(this_user, private_network.id)
      end
    rescue NetworkBundle::NetworkConfigurationsException => e
      network_settings = []
      GitHub.logger.error({
        msg: "failed to fetch network settings",
        fn: "hosted_compute_networking.show",
        enterprise_id: this_user.id,
        exception: e })
    end
    render_react_app(
      title: "Private Networks",
      payload: {
        privateNetworks: private_networks.map(&method(:network_settings_to_payload)),
        isEnterprise: false,
        actor: this_user.display_login
      },
      page_data: { selected_link: :hosted_compute_networking },
      layout: "layouts/stafftools/user/content",
    )
  end

  private

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create(verbose: true)
  end
end
