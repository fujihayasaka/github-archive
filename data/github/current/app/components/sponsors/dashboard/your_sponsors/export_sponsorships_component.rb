# typed: true
# frozen_string_literal: true

class Sponsors::Dashboard::YourSponsors::ExportSponsorshipsComponent < ApplicationComponent
  include SponsorsButtonsHelper

  def initialize(sponsorable: nil)
    @sponsorable = sponsorable
  end

  private

  def render?
    @sponsorable.present? && has_been_sponsored?
  end

  def has_been_sponsored?
    earliest_year.present?
  end

  memoize def earliest_year
    earliest_timestamp = @sponsorable.sponsors_activities
      .with_sponsorable_action
      .order(timestamp: :asc)
      .pick(:timestamp)

    earliest_timestamp&.year
  end

  def hydro_click_data
    sponsors_button_hydro_attributes(:SPONSORSHIPS_EXPORT, @sponsorable.display_login)
  end
end
