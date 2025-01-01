# typed: true
# frozen_string_literal: true

class Businesses::HostedComputeNetworkingController < Businesses::BusinessController
  require "network_bundle/network_configuration_client"
  include ReactHelper
  include BundleHelper
  include TagAttributeHelper

  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::HostedComputeNetworkingController#update",
  ]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations

  # From default page view
  depends_on_clusters ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Spokes,
    ApplicationRecord::Copilot,
    ApplicationRecord::Billing,
    optional: true

  javascript_bundle :settings
  sig { returns(String) }
  def self.react_bundle_name
    "network-configurations"
  end

  def show
    orgs_can_create_network_configurations = this_business.network_configuration_creation_by_org_enabled?

    update_path = enterprise_hosted_compute_networking_path(this_business)
    update_method = :patch
    add_csrf_token(update_path, update_method)

    render_react_app(
      payload: {
        orgsCanCreateNetworkConfigurations: orgs_can_create_network_configurations,
        updatePath: update_path,
        updateMethod: update_method
      },
      layout: "react_business",
      title: "Hosted compute networking",
      page_data: {
        selected_link: :hosted_compute_networking
      },
      ssr: true
    )
  end

  def update
    orgs_can_create_network_configurations = params[:orgsCanCreateNetworkConfigurations] == "true"
    if !orgs_can_create_network_configurations
      # Disable all network configurations associated with this business's organizations
      org_ids = this_business.organizations.pluck(:id)
      network_config_client.disable_organizations_configurations(this_business, org_ids)
    end
    this_business.set_network_configuration_creation_by_org(current_user, orgs_can_create_network_configurations)
    render json: {}, status: :ok
  rescue NetworkBundle::NetworkConfigurationsException => e
    GitHub.logger.error({
      msg: "failed to disable business' organizations' network configuration",
      fn: "hosted_compute_networking_controller.update",
      enterprise_id: this_business.id,
      exception: e })
    render json: {
      error: {
        message: e.message,
        code: e.code,
      }
    }, status: :unprocessable_entity
  end

  private

  sig { returns(NetworkBundle::NetworkConfigurationClient) }
  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end
end
