# typed: true
# frozen_string_literal: true

class Businesses::Actions::CustomImageVersionsController < Businesses::BusinessController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::Actions::CustomImageVersionsController#destroy",
  ]

  extend T::Sig
  include ReactHelper
  include Actions::LargerRunnersHelper
  include Actions::LargerRunnersControllerHelper
  include Actions::LargerRunners::CustomImagesHelper
  include ApplicationController::VerifiedFetchDependency

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
    ensure_tenant_exists(entity: current_business)
    is_custom_images_enabled?(entity: current_business)
  end

  javascript_bundle :settings

  sig { returns(String) }
  def self.react_bundle_name
    "custom-images"
  end

  sig { void }
  def index
    if is_custom_images_enabled?(entity: current_business)
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
        },
        page_data: { selected_link: :business_actions_settings_custom_images },
        title: "Custom image versions " + image.display_name + " · " + current_business.name,
        layout: "react_business",
        ssr: true,
      )
    else
      render_404
    end
  end

  sig { void }
  def destroy
    image_definition_id = params[:image_id]&.to_i
    return render_404 if !image_definition_id.present?

    version_specifier = params[:version]
    return render_404 if !valid_version_specifier?(version_specifier)

    return render_404 if !is_custom_images_enabled?(entity: current_business)

    resp = Launch::Twirp::larger_runners_client.delete_image_version(current_business, image_definition_id: image_definition_id, image_version: version_specifier)

    if !resp.call_succeeded?
      if resp.options&.fetch(:message, nil).to_s.include?("currently referenced by at least one pool")
        error_message = "Failed to delete custom image version because it's currently used by at least one runner."
      else
        error_message = "Failed to delete custom image version."
      end
      render json: { success: false, errors: [error_message] }, status: resp.status
    else
      render json: { success: true, errors: [] }, status: :ok
    end
  end
end
