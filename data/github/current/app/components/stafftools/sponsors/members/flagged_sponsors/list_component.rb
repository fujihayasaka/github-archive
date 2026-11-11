# typed: true
# frozen_string_literal: true

class Stafftools::Sponsors::Members::FlaggedSponsors::ListComponent < ApplicationComponent
  # flagged_sponsor_records - an Array of FraudFlaggedSponsor records
  def initialize(flagged_sponsor_records:)
    @flagged_sponsor_records = flagged_sponsor_records
  end

  private

  def render?
    GitHub.sponsors_enabled? && @flagged_sponsor_records.present?
  end
end
