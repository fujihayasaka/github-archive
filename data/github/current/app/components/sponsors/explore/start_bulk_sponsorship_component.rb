# typed: true
# frozen_string_literal: true

class Sponsors::Explore::StartBulkSponsorshipComponent < ApplicationComponent
  include SponsorsButtonsHelper

  SPONSORS_EXPLORE = :START_BULK_SPONSORSHIP_SPONSORS_EXPLORE
  USER_SPONSORING_TAB = :START_BULK_SPONSORSHIP_USER_SPONSORING_TAB
  ORG_SPONSORING_TAB = :START_BULK_SPONSORSHIP_ORG_SPONSORING_TAB
  UNKNOWN = :UNKNOWN

  LOCATIONS = {
    sponsors_explore: SPONSORS_EXPLORE,
    user_sponsoring_tab: USER_SPONSORING_TAB,
    org_sponsoring_tab: ORG_SPONSORING_TAB,
  }.freeze

  # location - symbol indicating where the component is being rendered
  # sponsor_login - optional String login of the User or Organization the viewer wants to sponsor as;
  #                 if nil, sponsorships will default to being from the current authenticated user
  def initialize(location:, sponsor_login: nil)
    @sponsor_login = sponsor_login
    @location = location
  end

  private

  attr_reader :sponsor_login

  def render?
    GitHub.sponsors_enabled? && logged_in?
  end

  def location
    LOCATIONS[@location] || UNKNOWN
  end

  def hydro_click_data
    sponsors_button_hydro_attributes(location, nil)
  end

  def bulk_sponsorships_path
    sponsors_bulk_sponsorship_frequencies_path(sponsor: sponsor_login)
  end
end
