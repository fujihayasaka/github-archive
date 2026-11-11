# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::FlaggedSponsors::FlaggedSponsorComponent < ApplicationComponent
  # flagged_record - a FraudFlaggedSponsor.
  # sponsor - the User associated with the FraudFlaggedSponsor record.
  def initialize(flagged_record:, sponsor:)
    @flagged_record = flagged_record
    @sponsor = sponsor
  end

  private

  attr_reader :flagged_record, :sponsor

  def render?
    flagged_record.present?
  end

  def sponsor_login
    sponsor&.login || User.ghost.login
  end

  def formatted_flagged_at
    flagged_record.created_at.strftime("%Y-%m-%d %I:%M%P")
  end
end
