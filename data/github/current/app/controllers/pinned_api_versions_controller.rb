# typed: true
# frozen_string_literal: true

class PinnedApiVersionsController < ApplicationController
  before_action :login_required
  before_action :sudo_filter

  def update
    new_api_version = params[:pinned_api_version].present? ? params[:pinned_api_version] : nil
    current_user.update(pinned_api_version: new_api_version)
    if current_user.errors.any?
      flash[:error] = current_user.errors.full_messages.to_sentence
    end
    redirect_to :back
  end

  private def target_for_conditional_access
    current_user
  end
end
