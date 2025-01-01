# typed: true
# frozen_string_literal: true

class Stafftools::Users::HostedComputeNetworkingController < StafftoolsController
  extend T::Sig
  include ReactHelper
  include NetworkConfigurationsHelper

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

  def show
    begin
      network_configurations = network_config_client.list_configurations(this_user)
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
        isEnterprise: false
      },
      page_data: { selected_link: :hosted_compute_networking },
      layout: "layouts/stafftools/user/content",
      ssr: true,
    )
  end

  private

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end
end
