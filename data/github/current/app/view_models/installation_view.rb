# typed: true
# frozen_string_literal: true

class InstallationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :integratable, :session

  # Public: Does the user have an active subscription to the OAuth app or
  # integration listed in the Marketplace.
  #
  # Returns a Boolean.
  def current_user_has_active_subscription_for_marketplace_listing?
    if current_user && marketplace_listing_id.present?
      current_user.any_active_subscription_items_for_owned_accounts?(marketplace_listing)
    end
  end

  # Public: Does the account have a paid subscription to the app being
  # authorized or installed?
  #
  # account - a User or Organization.
  #
  # Returns a Boolean.
  def paid_marketplace_plan_purchased_by?(account)
    return false if marketplace_listing.blank?
    paid_plan_ids = marketplace_listing.paid_listing_plans.pluck(:id)
    account.has_active_subscription_item_for?(paid_plan_ids)
  end

  # Public: Has the user navigated to the current view from the Marketplace.
  #
  # Returns a Boolean.
  def came_from_marketplace?
    return false if marketplace_listing.blank?
    last_marketplace_listing_id = session[:last_click_marketplace_listing_id]
    last_marketplace_listing_id.present? && last_marketplace_listing_id == integratable.marketplace_listing.id
  end

  # Public: CSS style rule for setting the logo background.
  #
  # Returns a String.
  def logo_background_color_style_rule
    "background-color:##{integratable.preferred_bgcolor}"
  end

  # Public: ID of Marketplace listing associated with integratable.
  #
  # Returns an Integer or nil.
  def marketplace_listing_id
    if marketplace_listing.present?
      marketplace_listing.id
    end
  end

  private

  def marketplace_listing
    integratable.marketplace_listing
  end
end
