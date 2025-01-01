# typed: true
# frozen_string_literal: true

require "test_helper"

class BiztoolsYearlySalesReportTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    Timecop.freeze(Time.new(2016, 3, 31)) do
      create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: 30000
    end

    Timecop.freeze(Time.new(2016, 4, 19)) do
      create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: 8400
    end

    @report = Biztools::YearlySalesReport.new(2016, 4)
  end

  context "#filename" do
    test "generates a filename" do
      assert_equal "yearly-transactions-2016-04.csv", @report.filename
    end
  end

  context "#generate" do
    test "returns a string-rendered csv" do
      headers = @report.csv_headers.join(",")
      assert_match headers, @report.generate
    end

    test "includes yearly transaction" do
      assert_match("84.00,settled,recurring-charge", @report.generate)
    end

    test "excludes transactions outside requested month" do
      refute_match("300.00,settled,recurring-charge", @report.generate)
    end
  end
end
