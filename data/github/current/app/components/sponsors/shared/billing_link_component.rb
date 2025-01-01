# typed: true
# frozen_string_literal: true

class Sponsors::Shared::BillingLinkComponent < ApplicationComponent
  def initialize(sponsor:)
    @sponsor = sponsor
  end

  def call
    content_tag(:p, text, class: "color-fg-muted mt-3")
  end

  private

  def render?
    return false unless GitHub.sponsors_enabled?
    return false unless @sponsor.present?
    return false unless logged_in?
    return false unless current_user.potential_sponsor_ids.include?(@sponsor.id)
    true
  end

  def text
    safe_join([
      "You can see ",
      possessive,
      " sponsorship billing in the ",
      billing_settings_link,
      "."
    ])
  end

  def org?
    @sponsor.organization? ? true : false
  end

  def possessive
    if org?
      safe_join([content_tag(:strong, @sponsor), "'s"])
    else
      "your"
    end
  end

  def billing_settings_link
    render Primer::Beta::Link.new(
      href: billing_setttings_sponsorships_url,
      test_selector: "sponsor-billing-link",
      classes: "Link--inTextBlock",
    ).with_content("billing settings")
  end

  def billing_setttings_sponsorships_url
    anchor = "sponsorship-history"
    if org?
      settings_org_billing_path(@sponsor.display_login, anchor: anchor)
    else
      settings_user_billing_path(anchor: anchor)
    end
  end
end
