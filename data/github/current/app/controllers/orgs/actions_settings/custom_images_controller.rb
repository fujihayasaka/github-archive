# typed: true
# frozen_string_literal: true

class Orgs::ActionsSettings::CustomImagesController < Orgs::Controller
  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "Orgs::ActionsSettings::CustomImagesController#destroy",
  ]

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
      ssr: true,
    )
  end

  sig { void }
  def destroy
    image_definition_id = params[:id]&.to_i
    return render_404 if !image_definition_id.present?

    resp = Launch::Twirp::larger_runners_client.delete_image_definition(current_organization, image_definition_id: image_definition_id)

    if !resp.call_succeeded?
      if resp.options&.fetch(:message, nil).to_s.include?("because it's currently referenced by at least one pool")
        error_message = "Failed to delete custom image because it's currently used by at least one runner."
      else
        error_message = "Failed to delete custom image."
      end
      render json: { success: false, errors: [error_message] }, status: resp.status
    else
      render json: { success: true, errors: [] }, status: :ok
    end
  end
end
