# typed: true
# frozen_string_literal: true

class BetaEnrollmentsController < ApplicationController # rubocop:todo GitHub/ControllersShouldHaveTests

  before_action :login_required
  before_action :ensure_feature

  include OrganizationsHelper

  def create
    if current_user.enable_feature_preview(params[:feature])
      flash[successful_flash_key] = successful_enrollment_message
    else
      flash[failed_flash_key] = failed_enrollment_message
    end

    after_feature_preview_redirect
  end

  def destroy
    if current_user.disable_feature_preview(params[:feature])
      flash[successful_flash_key] = successful_unenrollment_message
    else
      flash[failed_flash_key] = failed_unenrollment_message
    end

    after_feature_preview_redirect
  end

  private

  def successful_flash_key
    :notice
  end

  def failed_flash_key
    :error
  end

  def successful_enrollment_message
    "You're now in the beta! It may take a minute to see changes."
  end

  def failed_enrollment_message
    "Sorry, we couldn't add you to the beta at this time."
  end

  def successful_unenrollment_message
    "You're now unenrolled from the beta. It may take a minute to see changes."
  end

  def failed_unenrollment_message
    "Sorry, we couldn't remove you from the beta at this time."
  end

  def after_feature_preview_redirect
    if params[:return_to].present?
      safe_redirect_to params[:return_to]
    else
      redirect_to home_path
    end
  end

  def ensure_feature
    render_404 unless params[:feature].present?
  end
end
