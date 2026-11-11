# typed: true
# frozen_string_literal: true

class MarketplaceListingScreenshotsController < ApplicationController

  before_action :marketplace_required
  before_action :login_required
  before_action :require_xhr, only: [:update, :destroy]
  before_action :require_this_listing_screenshot
  before_action :require_this_listing_screenshot_adminable

  stylesheet_bundle :marketplace

  def update
    success = false
    resequence = screenshot_params.has_key?(:previousScreenshotId)

    if resequence
      previous_screenshot = Marketplace::ListingScreenshot.find_by(id: screenshot_params[:previousScreenshotId])
      success = this_listing_screenshot.resequence(after_screenshot: previous_screenshot)
    else
      this_listing_screenshot.caption = screenshot_params[:caption]
      success = this_listing_screenshot.save
    end

    unless success
      errors = this_listing_screenshot.errors.messages.values.join(", ")
      message = "Could not #{resequence ? 'resequence' : 'update'} Marketplace listing screenshot: #{errors}"

      return render json: { error: message }, status: :unprocessable_entity
    end

    head :ok
  end

  def destroy
    unless this_listing_screenshot.destroy
      errors = this_listing_screenshot.errors.full_messages.join(", ")
      message = "Could not delete Marketplace listing screenshot: #{errors}"

      return render json: { error: message }, status: :unprocessable_entity
    end

    head :ok
  end

  private

  def screenshot_params
    params[:marketplace_listing_screenshot].permit(:caption, :previousScreenshotId)
  end

  def target_for_conditional_access
    this_listing_screenshot&.listing&.owner || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  memoize def this_listing_screenshot
    Marketplace::ListingScreenshot.find_by(id: params[:id])
  end

  def require_this_listing_screenshot
    render_404 if this_listing_screenshot.nil?
  end

  def require_this_listing_screenshot_adminable
    render_404 unless this_listing_screenshot.adminable_by?(current_user)
  end
end
