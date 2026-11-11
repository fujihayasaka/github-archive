# typed: true
# frozen_string_literal: true

class Stafftools::HostedComputeNetworkingController < StafftoolsController
  include ApplicationController::VerifiedFetchDependency

  before_action :dotcom_required
  before_action :network_settings_stafftools_enabled

  allow_verified_fetch only: [:search, :subnets]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Ballast,
    ApplicationRecord::Spokes,
    only: [:index, :search, :subnets]

  sig { returns(String) }
  def self.react_bundle_name
    "network-settings-stafftools"
  end

  def index
    respond_with_react(
      payload: IndexRoutePayload.new(
        search_results: [],
        search_query: ""
      ),
      title: "Hosted Compute Networking",
      layout: "layouts/stafftools/react_stafftools"
    )
  end

  def search # rubocop:todo GitHub/UseRestfulActions
    search_ids = params[:search_ids].to_s.split(",").map(&:strip).reject(&:blank?)

    if search_ids.empty?
      return render json: { error: "No search IDs provided" }, status: :bad_request
    end

    begin
      results = network_config_client.stafftools_search_settings(search_ids)
      render json: { results: results }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to search network settings",
        fn: "hosted_compute_networking.search",
        exception: e
      })
      render json: { error: e.message }, status: :bad_request
    end
  end

  def subnets # rubocop:todo GitHub/UseRestfulActions
    subnet_ids = params[:subnet_ids].to_s.split(",").map(&:strip).reject(&:blank?)

    if subnet_ids.empty?
      return render json: { error: "No subnet IDs provided" }, status: :bad_request
    end

    begin
      results = network_config_client.stafftools_search_subnets(subnet_ids)
      render json: { results: results }, status: :ok
    rescue NetworkBundle::NetworkConfigurationsException => e
      GitHub.logger.error({
        msg: "failed to search subnets",
        fn: "hosted_compute_networking.subnets",
        exception: e
      })
      render json: { error: e.message }, status: :bad_request
    end
  end

  private

  class IndexRoutePayload < ReactPayload::Base
    def route_id
      "networkSettingsSearchRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        searchResults: @search_results,
        searchQuery: @search_query,
      }
    end
  end

  def network_config_client
    NetworkBundle::NetworkConfigurationClient.create
  end

  def network_settings_stafftools_enabled
    render_404 unless GitHub.network_settings_stafftools_enabled?(current_user)
  end
end
