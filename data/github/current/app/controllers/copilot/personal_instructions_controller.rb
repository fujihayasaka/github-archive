# typed: true
# frozen_string_literal: true

class Copilot::PersonalInstructionsController < ApplicationController
  include ApplicationController::JsonDependency
  include ApplicationController::VerifiedFetchDependency

  before_action :login_required
  before_action :require_copilot_access
  before_action :try_parse_json_params, only: [:create]
  allow_verified_fetch only: [:create]

  sig { void }
  def create
    # This does an upsert. If the personal instructions are not created yet it will create one. Otherwise, it will update.
    personal_instructions = Copilot::CustomInstructions.find_or_initialize_by(owner_id: current_user.id, owner_type: "User")
    personal_instructions.prompt = params[:prompt]
    if personal_instructions.save
      head :ok
    else
      render json: { errorMessage: personal_instructions.errors.full_messages.to_sentence }, status: :unprocessable_entity
    end
  end

  private

  def login_required
    render_404 unless logged_in?
  end

  def require_copilot_access
    render_404 unless Copilot::Public::User.new(current_user).has_copilot_access?
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
