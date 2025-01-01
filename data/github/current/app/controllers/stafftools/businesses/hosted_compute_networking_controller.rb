# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::HostedComputeNetworkingController < Stafftools::Businesses::BusinessBaseController
  include NetworkConfigurationsHelper
  include Actions::RunnerGroupsHelper

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
    only: [:show, :index]

  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations"
  end

  def index
    begin
      all_runner_groups = Actions::RunnerGroup.for_entity(this_business, include_runners: true, include_hosted_runner_groups: true)
      runner_groups = all_runner_groups.filter { |group| !group.hosted? }

      network_configurations = network_config_client.list_configurations(this_business)
      network_configurations.each do |network_config|
        network_config.runner_groups = network_config.runner_groups
          .map do |runner_group_payload|
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
        fn: "hosted_compute_networking.index",
        enterprise_id: this_business.id,
        exception: e })
    end
    render_react_app(
      title: "Hosted compute networking",
      payload: {
        networkConfigurations: network_configurations.map(&method(:network_config_to_payload)),
        isEnterprise: true,
        actor: this_business.display_login,
      },
      page_data: { selected_link: :hosted_compute_networking },
    )
  end

  def show
    begin
      network_configuration_id = params[:id].to_s
      network_config = network_config_client.get_configuration(this_business, network_configuration_id)
      private_networks = network_config.network_setting_references.map do |private_network|
        network_config_client.get_settings(this_business, private_network.id)
      end
    rescue NetworkBundle::NetworkConfigurationsException => e
      private_networks = []
      GitHub.logger.error({
        msg: "failed to fetch network settings",
        fn: "hosted_compute_networking.show",
        enterprise_id: this_business.id,
        exception: e })
    end
    render_react_app(
      title: "Private Networks",
      payload: {
        privateNetworks: private_networks.map(&method(:network_settings_to_payload)),
        isEnterprise: true,
        actor: this_business.display_login
      },
      page_data: { selected_link: :hosted_compute_networking, sidebar: :policies },
    )
  end

  private

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create(verbose: true)
  end
end
