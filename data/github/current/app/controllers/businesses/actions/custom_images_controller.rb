# typed: true
# frozen_string_literal: true

class Businesses::Actions::CustomImagesController < Businesses::BusinessController
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Businesses::Actions::CustomImagesController#destroy",
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
    T.bind(self, Businesses::Actions::CustomImagesController)
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
    add_client_feature_flag([:ims_customer_image_definitions_limit_increase], entity: this_business)

    navigation_paths = {
      policies: settings_actions_enterprise_path(this_business.slug),
      runners: settings_actions_runners_enterprise_path(this_business.slug),
      runnerGroups: settings_actions_runner_groups_enterprise_path(this_business.slug),
      customImages: settings_actions_custom_images_enterprise_path(this_business.slug),
      oidcConfiguration: settings_actions_oidc_configuration_enterprise_path(this_business.slug)
    }

    render_react_app(
      payload: {
        entityLogin: this_business.display_login,
        images: get_transformed_custom_images_models(entity: this_business, query_versions: false),
        isEnterprise: true,
        canWriteCustomImages: true,
        navigationPaths: navigation_paths,
      },
      title: "Custom images · #{this_business.name}",
      layout: "react_business",
      page_data: {
        selected_link: :business_actions_settings_custom_images,
        sidebar: :policies,
      },
    )
  end

  sig { void }
  def destroy
    result = delete_customer_image(entity: current_business, image_id: params[:id], actor: current_user)
    if result[:status] == :not_found
      render_404
    else
      render json: { success: result[:success], errors: result[:errors] }, status: result[:status]
    end
  end
end
