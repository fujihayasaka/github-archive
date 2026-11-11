# typed: true
# frozen_string_literal: true

class Copilot::CopilotSpaces::VisibilitySettingsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :login_required
  before_action :require_copilot_spaces_feature_enabled
  before_action :require_xhr

  allow_verified_fetch only: [:show]
  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  depends_on_clusters ApplicationRecord::Mysql1, ApplicationRecord::IamAbilities,
                      ApplicationRecord::Collab, ApplicationRecord::Copilot

  def show
    copilot_space = CopilotSpace.for_owner_login_and_number!(params[:owner], params[:number])
    return render_404 unless copilot_space.owner.organization?
    return render_404 unless copilot_space.owner.direct_or_team_member?(current_user)
    count = copilot_space.owner.visible_user_ids_for(current_user).size
    render json: { member_count: count }
  end

  private

  def resource_for_conditional_access
    return :no_resource_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
    current_user
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end
end
