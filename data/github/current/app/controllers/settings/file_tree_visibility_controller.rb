# typed: true
# frozen_string_literal: true

class Settings::FileTreeVisibilityController < ApplicationController
  include Settings::ControllerMethods
  include ApplicationController::VerifiedFetchDependency

  before_action :require_xhr
  allow_verified_fetch only: [:update]

  def update
    return head :not_found unless logged_in?
    return head :not_found unless params[:file_tree_visible].present?

    value = ActiveModel::Type::Boolean.new.cast(params[:file_tree_visible])

    ActiveRecord::Base.connected_to(role: :writing) do
      current_user.settings.set!(:pull_request_file_tree_visible, value)
    end

    head :ok
  end
end
