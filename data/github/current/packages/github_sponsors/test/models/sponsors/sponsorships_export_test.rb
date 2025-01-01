# typed: true
# frozen_string_literal: true

require "test_helper"

class Sponsors::SponsorshipExportTest < GitHub::TestCase

  fixtures do
    @sponsor = create(:organization)
    @active_sponsorship = create(:sponsorship, sponsor: @sponsor)
    @inactive_sponsorship = create(:sponsorship, :inactive, sponsor: @sponsor)
  end

  if GitHub.sponsors_enabled?
    test "generates a CSV with the required headers" do
      export = Sponsors::SponsorshipsExport.new(
        sponsor: @sponsor,
        active: true
      ).csv

      expected_headers = %w[
        sponsor_login
        maintainer_login
        description
      ]

      assert_equal expected_headers, CSV.parse(export).first
    end

    test "CSV contains active sponsorships only when active true" do
      export = Sponsors::SponsorshipsExport.new(
        sponsor: @sponsor,
        active: true
      ).csv

      csv = T.unsafe(CSV.parse(export, headers: true))
      assert_equal 1, csv.count

      row = csv.first

      assert_equal @sponsor.login, row["sponsor_login"]
      assert_equal @active_sponsorship.sponsorable.login, row["maintainer_login"]
      assert_equal @active_sponsorship.amount_per_cycle, row["description"]
    end

    test "CSV contains inactive sponsorships only when active false" do
      export = Sponsors::SponsorshipsExport.new(
        sponsor: @sponsor,
        active: false
      ).csv

      csv = T.unsafe(CSV.parse(export, headers: true))
      assert_equal 1, csv.count

      row = csv.first
      assert_equal @sponsor.login, row["sponsor_login"]
      assert_equal @inactive_sponsorship.sponsorable.login, row["maintainer_login"]
      assert_equal @inactive_sponsorship.amount_per_cycle, row["description"]
    end

    test "filename is <sponsor>-sponsorships-<current date>.csv" do
      travel_to(Date.parse("2024-01-01")) do
        export = Sponsors::SponsorshipsExport.new(
          sponsor: @sponsor,
          active: false
        )

        assert_equal("#{@sponsor}-sponsorships-2024-01-01T00:00:00+00:00.csv", export.filename)
      end
    end

    test "CSV has headers only when there are no sponsorships" do
      export = Sponsors::SponsorshipsExport.new(
        sponsor: create(:organization),
        active: false
      ).csv

      expected_headers = %w[
        sponsor_login
        maintainer_login
        description
     ]

      assert_equal [expected_headers], CSV.parse(export).to_a
    end
  end
end
