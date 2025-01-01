# typed: true
# frozen_string_literal: true

class Settings::CopilotChatVisibilityController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  def update
    return head :not_found unless logged_in?
    return head :not_found unless params[:copilot_chat_visible].present?

    value = ActiveModel::Type::Boolean.new.cast(params[:copilot_chat_visible])

    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.settings.set!(:copilot_chat_visible, value)
    end

    head :ok
  end
end
