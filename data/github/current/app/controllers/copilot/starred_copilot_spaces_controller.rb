# typed: true
# frozen_string_literal: true

class Copilot::StarredCopilotSpacesController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency
  include CopilotSpaces::FeaturePreviewRedirect

  before_action :login_required
  before_action :require_copilot_spaces_feature_enabled
  before_action :parse_json_params, only: [:create]

  allow_verified_fetch only: [:create, :destroy]

  rescue_from ActiveRecord::RecordNotFound, with: :render_404

  def create
    return render_404 unless copilot_space.readable_by?(current_user)

    if current_user.star_custom_copilot(copilot_space)
      head :created
    else
      render json: { errorMessages: format_error_messages(copilot_space.errors) }, status: :unprocessable_entity
    end
  end

  def destroy
    return render_404 unless starred_copilot_space
    if current_user.unstar_custom_copilot(starred_copilot_space)
      head :ok
    else
      render json: { errorMessages: format_error_messages(starred_copilot_space.errors) }, status: :unprocessable_entity
    end
  end

  private

  sig { returns(CopilotSpace) }
  memoize def copilot_space
    # User.find_by_login(<org_login>) will still return an Organization object.
    owner = User.find_by_login(params[:owner])
    raise ActiveRecord::RecordNotFound unless owner.present?

    copilot_space = CopilotSpace.find_by!(owner: owner, number: params[:number])
    assign_user_and_cap(copilot_space)

    copilot_space
  end

  def format_error_messages(errors)
    errors.messages.transform_values do |error_messages|
      # This converts the error messages from an array of strings, to a single
      # string sentence for easy display in the UI
      error_messages.to_sentence
    end
  end

  memoize def starred_copilot_space
    current_user.starred_copilot_spaces.find_by(copilot_space: copilot_space)
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless logged_in? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    current_user
  end

  def assign_user_and_cap(copilot_space)
    copilot_space.current_user = current_user
    copilot_space.cap_filter = cap_filter
  end
end
