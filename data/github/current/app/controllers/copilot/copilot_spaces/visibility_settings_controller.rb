# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpaces::VisibilitySettingsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :require_copilot_spaces_feature_enabled
  before_action :require_feature_enabled
  before_action :login_required
  before_action :require_xhr

  allow_verified_fetch only: [:show]
  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::IamAbilities,
                      ApplicationRecord::Collab, ApplicationRecord::Copilot

  def show
    copilot_space = CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
    if copilot_space.owner.organization?
      count = copilot_space.owner.visible_user_ids_for(current_user).size
      render json: { member_count: count }
    else
      render json: { error: "Not found" }, status: :not_found
    end
  end

  private

  def require_feature_enabled
    render_404 unless user_feature_enabled?(:copilot_custom_copilots_org_owned) &&
                      user_feature_enabled?(:copilot_custom_copilots_visibility)
  end

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
