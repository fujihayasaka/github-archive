# typed: true
# frozen_string_literal: true

require "test_helper"

class BiztoolsYearlyRefundsReportTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    Timecop.freeze(Time.new(2016, 3, 31)) do
      txn = create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: 30000

      create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: -30000,
        transaction_type: "refund",
        sale_transaction_id: txn.transaction_id
    end

    Timecop.freeze(Time.new(2016, 4, 19)) do
      txn = create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: 8400

      create :billing_transaction,
        renewal_frequency: :yearly,
        amount_in_cents: -8400,
        transaction_type: "refund",
        sale_transaction_id: txn.transaction_id
    end

    @report = Biztools::YearlyRefundsReport.new(2016, 4)
  end

  context "#filename" do
    test "generates a filename" do
      assert_equal "yearly-refunds-2016-04.csv", @report.filename
    end
  end

  context "#generate" do
    test "returns a string-rendered csv" do
      headers = @report.csv_headers.join(",")
      assert_match headers, @report.generate
    end

    test "includes yearly refund" do
      assert_match("-84.00,settled,refund", @report.generate)
    end

    test "excludes refunds outside requested month" do
      refute_match("-300.00,settled,refund", @report.generate)
    end
  end
end
