# typed: strict
# frozen_string_literal: true

class Sponsors::BulkSponsorships::FrequenciesComponent < ApplicationComponent
  extend T::Sig

  sig { params(sponsor: GitHubSponsors::Types::Sponsor).void }
  def initialize(sponsor:)
    @sponsor = sponsor
  end

  private

  sig { returns T::Boolean }
  def invoiced?
    @sponsor.sponsors_invoiced?
  end

  sig { returns String }
  def one_time_imports_path
    new_sponsors_bulk_sponsorship_imports_path(sponsor: @sponsor, frequency: "one-time")
  end

  sig { returns String }
  def recurring_imports_path
    new_sponsors_bulk_sponsorship_imports_path(sponsor: @sponsor, frequency: "recurring")
  end
end
