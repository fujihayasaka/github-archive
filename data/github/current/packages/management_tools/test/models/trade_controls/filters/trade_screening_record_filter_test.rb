# typed: true
# frozen_string_literal: true

require "test_helper"

class TradeControls::Filters::TradeScreeningRecordFilterTest < GitHub::TestCase
  context ".filter_records" do
    test "returns sdn blocked marketplace creators when filter is :flagged_marketplace_creator" do
      mp_account = create :account_screening_profile, :hit_in_review, :marketplace_app_owner
      create :account_screening_profile, :marketplace_app_owner
      create :account_screening_profile, :hit_in_review

      records = TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
        current_page: 1,
        trade_screening_status: "flagged_marketplace_creator"

      assert_equal records, [mp_account]
    end

    test "returns accounts that have been in a hit in review screening status for over 2 days when filter is :hit_in_review_breached" do
      breach_account = create :account_screening_profile, :hit_in_review, last_trade_screen_date: 3.days.ago
      create :account_screening_profile, :not_screened
      create :account_screening_profile, :true_match

      records = TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
        current_page: 1,
        trade_screening_status: "hit_in_review_breached"

      assert_equal records, [breach_account]
    end

    test "returns records with matching trade_screening_status when one is provided" do
      lic_r = create :account_screening_profile, :lic_r
      create :account_screening_profile, :not_screened
      create :account_screening_profile, :hit_in_review

      records = TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
        current_page: 1,
        trade_screening_status: "lic_r"

      assert_equal records, [lic_r]
    end

    test "paginates the results do" do
      create :account_screening_profile, :lic_r
      create :account_screening_profile, :hit_in_review
      create :account_screening_profile, :hit_in_review

      records = TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
        current_page: 1,
        per_page: 1,
        trade_screening_status: "hit_in_review"

      assert_equal 1, records.size
      assert_equal 2, records.total_entries

      records = TradeControls::Filters::TradeScreeningRecordFilter.filter_records \
        current_page: 1,
        per_page: 2,
        trade_screening_status: "hit_in_review"

      assert_equal 2, records.count
      assert_equal 2, records.total_entries
    end
  end
end
