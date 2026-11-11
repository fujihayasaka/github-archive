# typed: true
# frozen_string_literal: true

class Sponsors::Accounts::CardComponent < ApplicationComponent
  include ActionView::Helpers::NumberHelper

  attr_reader :account

  def initialize(account:)
    @account = account
  end

  private

  def render?
    account.present?
  end

  def display_login
    account.display_login
  end

  def listing_state
    sponsors_listing&.current_state_name
  end

  def description
    if sponsors_listing.nil?
      "This account has not applied to join GitHub Sponsors."
    elsif sponsors_listing.waiting_to_be_reviewed?
      "This GitHub Sponsors profile is waiting to be reviewed by GitHub."
    elsif sponsors_listing.draft?
      "You've been accepted to join the program! Set up your GitHub Sponsors profile now."
    else
      sponsors_listing.short_description.presence
    end
  end

  memoize def show_country_of_residence_warning?
    sponsors_listing&.encourage_setting_country_of_residence?
  end

  memoize def sponsors
    if sponsors_listing
      account.sponsors_visible_to(current_user).limit(3)
    else
      []
    end
  end

  memoize def sponsors_count
    if sponsors_listing
      account.total_sponsors
    else
      0
    end
  end

  def for_organization?
    account.organization?
  end

  def public_sponsors_listing?
    sponsors_listing&.approved?
  end

  def action_button_text
    if sponsors_listing.nil? || signup_in_progress_without_warnings?
      "Get sponsored"
    elsif sponsors_listing.accepted_into_sponsors?
      "Dashboard"
    else
      "Manage"
    end
  end

  def action_button_url
    if signup_in_progress_without_warnings?
      sponsorable_signup_path(account)
    elsif sponsors_listing&.accepted_into_sponsors?
      if show_country_of_residence_warning?
        sponsorable_dashboard_settings_path(account)
      else
        sponsorable_dashboard_path(account)
      end
    else
      sponsorable_signup_path(account)
    end
  end

  memoize def sponsors_listing
    account.sponsors_listing
  end

  memoize def monthly_funding
    if sponsors_listing
      cents = sponsors_listing.subscription_value
      Billing::Money.new(cents)
    else
      Billing::Money.zero
    end
  end

  memoize def signup_in_progress_without_warnings?
    return false if show_country_of_residence_warning?
    !!sponsors_listing&.signup_in_progress?
  end
end
