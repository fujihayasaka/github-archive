# typed: strict
# frozen_string_literal: true

class Sponsors::ManageSponsorshipComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsorship: Sponsorship).void }
  def initialize(sponsorship:)
    @sponsorship = sponsorship
  end

  sig { returns(String) }
  def call
    render Primer::Alpha::ActionMenu.new do |menu|
      menu.with_show_button(test_selector: "sponsorable-#{sponsorable.display_login}-button") { "Manage" }
      menu.with_item(**sponsorship_menu_item)
      menu.with_divider
      menu.with_item(**toggle_privacy_menu_item)
      menu.with_item(**toggle_email_menu_item) if sponsorship.active?
    end
  end

  private

  sig { returns(Sponsorship) }
  attr_reader :sponsorship

  sig { returns(T::Boolean) }
  def render?
    sponsorship.present?
  end

  sig { returns(String) }
  def manage_sponsorship_url
    sponsorable_sponsorships_path(sponsorable,
      sponsor: sponsor,
      tier_id: sponsorship.subscribable_id,
    )
  end

  sig { returns(String) }
  def update_sponsorship_url
    sponsorable_sponsorships_path(sponsorable,
      sponsor: sponsor,
    )
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def sponsorship_menu_item
    label, href = if sponsorship.patreon? && patreon_membership_link.present?
      ["Manage on Patreon", patreon_membership_link]
    elsif sponsorship.active? && !sponsorship.patreon?
      ["Manage sponsorship", manage_sponsorship_url]
    else
      ["Re-sponsor", sponsorable_path(sponsorable, sponsor: sponsor)]
    end

    {
      label: label,
      href: href,
      test_selector: "sponsors-manage-sponsorship-#{sponsorable.display_login}",
      data: { turbo: false },
    }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def toggle_privacy_menu_item
    {
      label: "Make #{opposite_privacy_level}",
      href: update_sponsorship_url,
      form_arguments: {
        method: :put,
        name: :privacy_level,
        value: opposite_privacy_level,
        html: { role: :none }, # See: https://github.com/github/accessibility-audits/issues/6654
      },
      test_selector: "sponsors-manage-privacy-#{sponsorable.display_login}",
      data: { turbo: false },
    }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def toggle_email_menu_item
    {
      label: "#{opposite_email_text_for(sponsorship)} email updates",
      href: update_sponsorship_url,
      form_arguments: {
        method: :put,
        name: :email_opt_in,
        value: opposite_email_value_for(sponsorship),
        html: { role: :none }, # See: https://github.com/github/accessibility-audits/issues/6654
      },
      data: { turbo: false },
      test_selector: "sponsors-manage-email-updates-#{sponsorable.display_login}"
    }
  end

  sig { returns(GitHubSponsors::Types::Sponsor) }
  def sponsor
    sponsorship.sponsor || User.ghost
  end

  sig { returns(GitHubSponsors::Types::Sponsorable) }
  def sponsorable
    sponsorship.sponsorable || User.ghost
  end

  sig { returns(T.nilable(String)) }
  def opposite_privacy_level
    sponsorship.opposite_privacy_level
  end

  sig { params(sponsorship: Sponsorship).returns(String) }
  def opposite_email_text_for(sponsorship)
    helpers.opposite_email_text_for(sponsorship)
  end

  sig { params(sponsorship: Sponsorship).returns(String) }
  def opposite_email_value_for(sponsorship)
    helpers.opposite_email_value_for(sponsorship)
  end

  sig { returns(T.nilable(String)) }
  def patreon_membership_link
    sponsorable.sponsors_patreon_membership_link
  end
end
