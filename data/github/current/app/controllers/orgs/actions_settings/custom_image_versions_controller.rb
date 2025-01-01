# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::CustomImageVersionsController < Orgs::Controller
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsSettings::CustomImageVersionsController#destroy",
  ]

  include Actions::LargerRunnersHelper
  include Actions::LargerRunnersControllerHelper
  include Actions::LargerRunners::CustomImagesHelper
  include ApplicationController::VerifiedFetchDependency
  include Actions::CustomImagesControllerHelper

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Copilot,
    only: [:index, :destroy]

  preload_features [:actions_custom_image, :larger_runners_custom_image_generation], only: [:index, :destroy]

  allow_verified_fetch only: [:destroy]

  before_action :login_required
  before_action :ensure_user_has_runner_custom_images_read_access, only: [:index]
  before_action :ensure_user_has_runner_custom_images_write_access, only: [:destroy]
  before_action do
    T.bind(self, Orgs::ActionsSettings::CustomImageVersionsController)
    ensure_larger_runners_enabled(entity: current_organization, actor: current_user, this_entity: this_organization)
    ensure_custom_images_enabled(entity: current_organization)
    ensure_tenant_exists(entity: current_organization)
  end

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "custom-images"
  end

  sig { void }
  def index
    image_id = params[:image_id]&.to_i
    image = get_custom_image(entity: current_organization, image_id: image_id)
    image_versions = get_detailed_transformed_image_versions_models(entity: current_organization, image: image)
    render_react_app(
      payload: {
        entityLogin: current_organization.display_login,
        imageDefinitionId: image_id,
        imageName: image&.display_name,
        imagesListPath: settings_org_actions_custom_images_path(current_organization),
        isEnterprise: false,
        latestVersion: image&.latest_version,
        versions: image_versions,
        canWriteCustomImages: this_organization.can_write_organization_runner_custom_images?(current_user)
      },
      page_data: { selected_link: :organization_actions_settings_custom_images },
      title: "Custom image versions " + image.display_name + " · " + current_organization.name,
      layout: "layouts/settings/actions_org_react",
    )
  end

  sig { void }
  def destroy
    result = delete_customer_image_version(entity: current_organization, image_id: params[:image_id], version: params[:version])
    if result[:status] == :not_found
      render_404
    else
      render json: { success: result[:success], errors: result[:errors] }, status: result[:status]
    end
  end
end
