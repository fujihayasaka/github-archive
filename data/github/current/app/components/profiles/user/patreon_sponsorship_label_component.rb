# typed: true
# frozen_string_literal: true

class Profiles::User::PatreonSponsorshipLabelComponent < ApplicationComponent
  sig { params(sponsorship: Sponsorship).void }
  def initialize(sponsorship:)
    @sponsorship = sponsorship
  end

  def call
    render Primer::Beta::Label.new(
      scheme: :info,
      ml: 2,
      test_selector: "patreon-sponsorship-label",
    ).with_content("Patreon")
  end

  private

  sig { returns Sponsorship }
  attr_reader :sponsorship

  sig { returns T.nilable(T::Boolean) }
  def render?
    sponsorship.patreon? && GitHub.sponsors_enabled? && logged_in? &&
      sponsorship.async_linked_or_direct_sponsor_billing_manageable_by?(current_user).sync
  end
end
