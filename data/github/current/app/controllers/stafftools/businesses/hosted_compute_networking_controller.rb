# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::HostedComputeNetworkingController < Stafftools::Businesses::BusinessBaseController
  extend T::Sig
  include ReactHelper
  include NetworkConfigurationsHelper

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

  def show
    begin
      network_configurations = network_config_client.list_configurations(this_business)
    rescue NetworkBundle::NetworkConfigurationsException => e
      network_configurations = []
      GitHub.logger.error({
        msg: "failed to fetch network configurations",
        fn: "hosted_compute_networking.show",
        enterprise_id: this_business.id,
        exception: e })
    end
    render_react_app(
      title: "Hosted compute networking",
      payload: {
        networkConfigurations: network_configurations.map(&method(:network_config_to_payload)),
        isEnterprise: false
      },
      page_data: { selected_link: :hosted_compute_networking },
      ssr: true,
    )
  end

  private

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end
end
