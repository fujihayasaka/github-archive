# typed: true
# frozen_string_literal: true

class Sponsors::BulkSponsorshipImports::SponsorableLinkComponent < ApplicationComponent
  # sponsorship_row - a Sponsors::BulkSponsorshipRow
  def initialize(sponsorship_row:)
    @sponsorship_row = sponsorship_row
  end

  def call
    render(Primer::Beta::Link.new(
      href: sponsorable_path(sponsorship_row.sponsorable_login),
      font_weight: :bold,
      scheme: :primary,
      data: link_data_attrs,
      target: "_blank", # new tab to not interrupt the checkout process
    ).with_content("@#{sponsorship_row.sponsorable_login}"))
  end

  private

  attr_reader :sponsorship_row

  def render?
    GitHub.sponsors_enabled? && sponsorship_row.present? && logged_in?
  end

  def link_data_attrs
    if sponsorship_row.for_organization?
      hovercard_data_attributes_for_org(login: sponsorship_row.sponsorable_login)
    else
      hovercard_data_attributes_for_user_login(sponsorship_row.sponsorable_login)
    end
  end
end
