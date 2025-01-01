# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::CustomImagesController < Orgs::Controller
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsSettings::CustomImagesController#destroy",
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
    T.bind(self, Orgs::ActionsSettings::CustomImagesController)
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
    render_react_app(
      payload: {
        entityLogin: current_organization.display_login,
        images: get_transformed_custom_images_models(entity: current_organization, query_versions: false),
        isEnterprise: false,
        canWriteCustomImages: this_organization.can_write_organization_runner_custom_images?(current_user)
      },
      title: "Custom images · " + current_organization.name,
      layout: "layouts/settings/actions_org_react",
      page_data: { selected_link: :organization_actions_settings_custom_images },
    )
  end

  sig { void }
  def destroy
    result = delete_customer_image(entity: current_organization, image_id: params[:id])
    if result[:status] == :not_found
      render_404
    else
      render json: { success: result[:success], errors: result[:errors] }, status: result[:status]
    end
  end
end
