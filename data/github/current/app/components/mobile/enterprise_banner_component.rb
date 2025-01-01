# typed: strict
# frozen_string_literal: true

class Mobile::EnterpriseBannerComponent < ApplicationComponent
  extend T::Sig

  EXCLUDED_CONTROLLERS = T.let(%w(sessions signup oauth).freeze, T::Array[String])

  sig { params(browser: Browser::Base, current_url: String, controller_name: T.nilable(String)).void }
  def initialize(browser:, current_url:, controller_name: nil)
    @browser = browser
    @current_url = current_url
    @controller_name = controller_name
  end

  sig { returns(T::Boolean) }
  def render?
    !!(GitHub.enterprise? &&
      !EXCLUDED_CONTROLLERS.include?(@controller_name) &&
      logged_in? &&
      relevant_mobile_app_exists?)
  end

  sig { returns(T::Boolean) }
  memoize def relevant_mobile_app_exists?
    result =
      if ios?
        Apps::Internal.oauth_application(:ios_mobile).present?
      elsif android?
        Apps::Internal.oauth_application(:android_mobile).present?
      end

    !!result
  end

  sig { returns(String) }
  def deeplink_url
    @current_url.sub(/\Ahttps?:\/\//, "github://")
  end

  sig { returns(String) }
  def mobile_store_url
    if ios?
      ios_mobile_app_store_url(campaign: "ghes")
    else
      android_mobile_app_store_url(campaign: "ghes")
    end
  end

  sig { returns(T::Boolean) }
  def ios?
    @browser.platform.ios?
  end

  sig { returns(T::Boolean) }
  def android?
    @browser.platform.android?
  end

  sig { returns(T::Boolean) }
  memoize def current_user_has_mobile_app?
    current_user.uses_mobile_app?
  end
end
