# typed: true
# frozen_string_literal: true

class Stafftools::Businesses::CustomImagesController < Stafftools::Businesses::BusinessBaseController
  include ApplicationController::VerifiedFetchDependency

  before_action :ensure_feature_enabled

  allow_verified_fetch only: [:index, :custom_image_details]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::RepositoriesPushes,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Memex,
    ApplicationRecord::Ballast,
    ApplicationRecord::Billing,
    only: [:index, :custom_image_details]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :custom_image_details],
    optional: true

  sig { returns(String) }
  def self.react_bundle_name
    "custom-images-stafftools"
  end

  # GET /stafftools/enterprises/:slug/custom_images/
  def index
    return redirect_to "/" unless this_business.present?

    base_url = Rails.application.routes.url_helpers.stafftools_enterprise_custom_images_path(this_business)
    image_definitions_resp = HostedComputeIms::Twirp.customer_images_client.list_customer_image_definitions(owner: this_business)

    if image_definitions_resp.call_succeeded
      image_definitions = image_definitions_resp.value&.image_definitions || []
    else
      GitHub.logger.error({
        msg: "failed to fetch custom image definitions",
        fn: "custom_images.index",
        status: image_definitions_resp.status,
        exception: image_definitions_resp.options[:message] })
      return render_404
    end

    payload = BusinessIndexRoutePayload.new(
      image_definitions: image_definitions.map(&method(:convert_image_definition_to_react_payload)),
      base_url: base_url,
      owner_id: this_business.next_global_id,
      retention_policies: retention_policies_react_payload(this_business)
    )

    respond_with_react(
      payload: payload,
      title: "Custom Images",
      layout: "layouts/stafftools/business"
    )
  end

  # GET /stafftools/enterprises/:slug/custom_images/:image_definition_id
  def custom_image_details # rubocop:todo GitHub/UseRestfulActions
    return redirect_to "/" unless this_business.present?

    id = params[:image_definition_id].to_i

    base_url = Rails.application.routes.url_helpers.stafftools_enterprise_custom_images_path(this_business)
    image_definition_resp = HostedComputeIms::Twirp.customer_images_client.get_customer_image_definition(
      owner: this_business,
      image_definition_id: id
    )

    unless image_definition_resp.call_succeeded
      GitHub.logger.error({
        msg: "failed to fetch custom image definition",
        fn: "custom_images.custom_image_details",
        status: image_definition_resp.status,
        exception: image_definition_resp.options[:message]
      })
      return render_404
    end

    image_definition = image_definition_resp.value&.image_definition

    image_versions_resp = HostedComputeIms::Twirp.customer_images_client.list_customer_image_versions(
      owner: this_business,
      image_definition_id: id
    )

    if image_versions_resp.call_succeeded
      image_versions = image_versions_resp.value&.image_versions || []
    else
      GitHub.logger.error({
        msg: "failed to fetch custom image versions",
        fn: "custom_images.custom_image_details",
        status: image_versions_resp.status,
        exception: image_versions_resp.options[:message]
      })
      return render_404
    end

    runner_group = nil
    if image_definition&.runner_group_id.present?
      begin
        runner_group = Actions::RunnerGroup.get(this_business, id: image_definition&.runner_group_id&.value, is_ui_read: true)
      rescue
        GitHub.logger.error({
          msg: "failed to fetch runner group for custom image definition",
          fn: "custom_images.custom_image_details"
        })
      end
    end

    payload = BusinessImageDetailsRoutePayload.new(
      image_definition: convert_image_definition_to_react_payload(image_definition),
      image_versions: image_versions.map(&method(:convert_image_version_to_react_payload)),
      base_url: base_url,
      runner_group: convert_runner_group_to_react_payload(runner_group)
    )

    respond_with_react(
      payload: payload,
      title: "Custom Images",
      layout: "layouts/stafftools/business"
    )
  end

  private

  def convert_image_definition_to_react_payload(object)
    {
      id: object.id,
      name: object.name,
      ownerId: object.owner_id,
      osType: object.os_type,
      architecture: object.architecture,
      enabled: object.enabled,
      state: object.state,
      isImageGenerationSupported: object.is_image_generation_supported,
      runnerGroupId: object.runner_group_id,
      latestVersion: object.latest_version,
      latestVersionSizeGb: object.latest_version_size_gb,
      imageVersionsCount: object.image_versions_count,
      totalImageVersionsSizeGb: object.total_image_versions_size_gb,
    }
  end

  def convert_image_version_to_react_payload(object)
    {
      imageDefinitionId: object.image_definition_id,
      version: object.version,
      state: object.state,
      stateDetails: object.state_details,
      sizeGb: object.size_gb,
      createdAt: object.created_at,
      lastUsedAt: object.last_used_at,
    }
  end

  def convert_runner_group_to_react_payload(object)
    return nil unless object.present?

    {
      id: object.id,
      name: object.name,
    }
  end

  def retention_policies_react_payload(entity)
    {
      imageVersionsPerImageLimit: entity.custom_image_versions_per_image_limit,
      imageVersionUnusedAgeLimit: entity.custom_image_version_unused_age_limit,
      imageVersionMaxAgeLimit: entity.custom_image_version_max_age_limit
    }
  end

  def ensure_feature_enabled
    render_404 if GitHub.enterprise? || !GitHub.actions_enabled?
  end

  class BusinessIndexRoutePayload < ReactPayload::Base
    def route_id
      "customImagesEnterpriseRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        imageDefinitions: @image_definitions,
        baseUrl: @base_url,
        ownerId: @owner_id,
        retentionPolicies: @retention_policies
      }
    end
  end

  class BusinessImageDetailsRoutePayload < ReactPayload::Base
    def route_id
      "customImageVersionsEnterpriseRoute"
    end

    def initialize(**kwargs)
      kwargs.each do |k, v|
        instance_variable_set("@#{k}", v)
      end
    end

    def payload
      {
        imageDefinition: @image_definition,
        imageVersions: @image_versions,
        baseUrl: @base_url,
        runnerGroup: @runner_group
      }
    end
  end
end
