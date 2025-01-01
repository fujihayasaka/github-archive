# typed: strict
# frozen_string_literal: true

class Sponsors::SponsorshipsExport
  CSV_HEADERS = T.let(%w[
    sponsor_login
    maintainer_login
    description
  ].freeze, T::Array[String])

  sig { returns(String) }
  attr_reader :csv

  sig { returns(String) }
  attr_reader :filename

  sig { params(sponsor: GitHubSponsors::Types::Sponsor, active: T::Boolean).void }
  def initialize(sponsor:, active:)
    @sponsor = sponsor
    @active = active
    @csv = T.let(generate_csv, String)
    @filename = T.let("#{@sponsor}-sponsorships-#{DateTime.current}.csv", String)
  end

  private

  sig  { returns String }
  def generate_csv
    @csv = CSV.generate(encoding: Encoding::UTF_8) do |csv|
      csv << CSV_HEADERS

      @sponsor.sponsorships_as_sponsor
      .where(active: @active)
      .each do |sponsorship|
        csv << [
         @sponsor.login,
         sponsorship.sponsorable&.login,
         sponsorship.amount_per_cycle,
      ]
      end
    end
  end
end
