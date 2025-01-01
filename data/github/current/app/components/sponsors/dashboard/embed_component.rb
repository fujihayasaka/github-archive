# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::EmbedComponent < ApplicationComponent

  extend T::Sig

  sig { params(sponsors_listing: SponsorsListing).void }
  def initialize(sponsors_listing:)
    @sponsors_listing = sponsors_listing
  end

  private

  attr_reader :sponsors_listing

  sig { returns(T::Boolean) }
  def render?
    sponsors_listing.present? && !sponsors_listing.disabled? && GitHub.sponsors_enabled? && logged_in?
  end

  sig { returns(String) }
  def sponsor_button_code_snippet
    snippet = <<-HTML
      <iframe
        src="#{sponsorable_button_url(sponsors_listing.sponsorable_login)}"
        title="Sponsor #{sponsors_listing.sponsorable_login}"
        height="32"
        width="114"
        style="border: 0; border-radius: 6px;"></iframe>
    HTML

    snippet.squish
  end

  sig { returns(String) }
  def sponsor_card_code_snippet
    snippet = <<-HTML
      <iframe
        src="#{sponsorable_card_url(sponsors_listing.sponsorable_login)}"
        title="Sponsor #{sponsors_listing.sponsorable_login}"
        height="225"
        width="600"
        style="border: 0;"></iframe>
    HTML

    snippet.squish
  end
end
