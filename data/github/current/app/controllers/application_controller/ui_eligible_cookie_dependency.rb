# typed: true
# frozen_string_literal: true

module ApplicationController::UIEligibleCookieDependency
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { ApplicationController }

  UI_ELIGIBLE_COOKIE = :ui_eligible
  UI_SERVICE_ELIGIBLE_FEATURE = :ui_service_eligible

  included do
    T.bind(self, T.class_of(ApplicationController))
    preload_features [UI_SERVICE_ELIGIBLE_FEATURE]
  end

  def set_ui_eligible_cookie
    # UI Service GLB routing is dotcom-only.
    return if GitHub.enterprise?
    return unless ui_eligible_cookie_request?

    # Avoid carrying stale routing state when this request is not eligible.
    if !ui_service_eligible?
      delete_ui_eligible_cookie
      return
    end

    # Feature preview enrollment is stored in Collab. If this action cannot
    # query Collab, leave the existing routing cookie state unchanged.
    return unless collab_cluster_declared?

    if command_palette_feature_preview_enabled?
      delete_ui_eligible_cookie
      return
    end

    cookies[UI_ELIGIBLE_COOKIE] = {
      value: "true",
      # Persist the GLB routing hint until eligibility changes.
      expires: 1.year.from_now,
      domain: cookie_domain,
    }
  end

  private

  def ui_service_eligible?
    FeatureFlag.vexi.enabled?(UI_SERVICE_ELIGIBLE_FEATURE, current_user, default: false)
  end

  def command_palette_feature_preview_enabled?
    user = current_user
    return false unless user

    user.command_palette_enabled?
  end

  def collab_cluster_declared?
    (Array(required_clusters) + Array(optional_clusters)).include?(ApplicationRecord::Collab)
  end

  def ui_eligible_cookie_request?
    # The UI Service routing cookie only affects browser page navigation.
    return false unless request.get?
    return false unless request.format.html?

    # Skip async and fragment requests that do not need a GLB routing hint.
    return false if request.xhr?
    return false if pjax?
    return false if turbo_frame_request?

    true
  end

  def delete_ui_eligible_cookie
    cookies.delete(UI_ELIGIBLE_COOKIE, domain: cookie_domain) if cookies[UI_ELIGIBLE_COOKIE].present?
  end
end
