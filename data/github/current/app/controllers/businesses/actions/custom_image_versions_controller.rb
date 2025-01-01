# typed: true
# frozen_string_literal: true

class Businesses::Actions::CustomImageVersionsController < Businesses::BusinessController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::Actions::CustomImageVersionsController#destroy",
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
  before_action :business_owner_required
  before_action :business_not_downgraded_to_free_plan_required
  before_action do
    T.bind(self, Businesses::Actions::CustomImageVersionsController)
    ensure_larger_runners_enabled(entity: current_business, actor: current_user, this_entity: this_business)
    ensure_custom_images_enabled(entity: current_business)
    ensure_tenant_exists(entity: current_business)
  end

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "custom-images"
  end

  sig { void }
  def index
    image_id = params[:image_id]&.to_i
    image = get_custom_image(entity: current_business, image_id: image_id)
    image_versions = get_detailed_transformed_image_versions_models(entity: current_business, image: image)
    render_react_app(
      payload: {
        entityLogin: this_business.display_login,
        imageDefinitionId: image_id,
        imageName: image&.display_name,
        imagesListPath: settings_actions_custom_images_enterprise_path(current_business),
        isEnterprise: true,
        latestVersion: image&.latest_version,
        versions: image_versions,
        canWriteCustomImages: true
      },
      page_data: { selected_link: :business_actions_settings_custom_images, sidebar: :policies },
      title: "Custom image versions #{image.display_name} · #{current_business.name}",
      layout: "react_business",
    )
  end

  sig { void }
  def destroy
    result = delete_customer_image_version(entity: current_business, image_id: params[:image_id], version: params[:version])
    if result[:status] == :not_found
      render_404
    else
      render json: { success: result[:success], errors: result[:errors] }, status: result[:status]
    end
  end
end
