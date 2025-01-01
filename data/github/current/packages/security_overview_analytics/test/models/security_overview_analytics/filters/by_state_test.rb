# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByStateTest < GitHub::TestCase
      include ::SecurityOverviewAnalytics::TestFixtures

      fixtures do
        @biz = create(:business)
        @org_admin = create(:user)
        @org = create(:organization, business: @biz, admin: @org_admin)
        @repo = create(:private_repository, owner: @org)
        create_repo_alerts(repository: @repo)
      end

      setup do
        @dbot_rel = DependabotAlertRevision.where(next_revision_date_id: Date::FUTURE_DATE_ID).order(:alert_number)
        @cs_rel = CodeScanningAlertRevision.where(next_revision_date_id: Date::FUTURE_DATE_ID).order(:alert_number)
        @ss_rel = SecretScanningAlertRevision.where(next_revision_date_id: Date::FUTURE_DATE_ID).order(:alert_number)
      end

      context "#apply" do
        context "no filters are provided" do
          test "does not filter on alerts" do
            assert_query_count(1) do
              ByState.new([], []).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 9, rows.size
              (0...9).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end

            assert_query_count(1) do
              ByState.new([], []).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 10, rows.size
              (0...10).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end

            assert_query_count(1) do
              ByState.new([], []).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 6, rows.size
              (0...6).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end
          end
        end

        context "inclusive filters" do
          test "filters by alert state" do
            assert_query_count(1) do
              ByState.new(["closed"], []).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], []).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 4, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
            end

            assert_query_count(1) do
              ByState.new(["closed"], []).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], []).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
              assert_equal 10, rows[4].alert_number
            end

            assert_query_count(1) do
              ByState.new(["closed"], []).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], []).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 1, rows.size
              assert_equal 6, rows[0].alert_number
            end
          end

          test "filters by OR'd alert states" do
            assert_query_count(1) do
              ByState.new(%w[open closed], []).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 9, rows.size
              (0...9).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end

            assert_query_count(1) do
              ByState.new(%w[open closed], []).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 10, rows.size
              (0...10).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end

            assert_query_count(1) do
              ByState.new(%w[open closed], []).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 6, rows.size
              (0...6).each do |i|
                alert_number = i + 1
                assert_equal alert_number, rows[i].alert_number
              end
            end
          end
        end

        context "exclusive filters" do
          test "filters by alert state" do
            assert_query_count(1) do
              ByState.new([], ["closed"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 4, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
            end
            assert_query_count(1) do
              ByState.new([], ["open"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end

            assert_query_count(1) do
              ByState.new([], ["closed"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
              assert_equal 10, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new([], ["open"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end

            assert_query_count(1) do
              ByState.new([], ["closed"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 1, rows.size
              assert_equal 6, rows[0].alert_number
            end
            assert_query_count(1) do
              ByState.new([], ["open"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
          end

          test "filters by AND'd alert states" do
            assert_query_count(1) do
              ByState.new([], %w[open closed]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new([], %w[open closed]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new([], %w[open closed]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
          end
        end

        context "inclusive and exclusive filters" do
          test "filters by alert state" do
            assert_query_count(1) do
              ByState.new(["closed"], ["open"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], ["closed"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 4, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
            end

            assert_query_count(1) do
              ByState.new(["closed"], ["open"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], ["closed"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
              assert_equal 10, rows[4].alert_number
            end

            assert_query_count(1) do
              ByState.new(["closed"], ["open"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["open"], ["closed"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 1, rows.size
              assert_equal 6, rows[0].alert_number
            end
          end

          test "filters by OR'd inclusive alert states and AND'd exclusive alert states" do
            assert_query_count(1) do
              ByState.new(%w[open closed], ["open"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(%w[open closed], ["closed"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_equal 4, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
            end
            assert_query_count(1) do
              ByState.new(["closed"], %w[open closed]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new(%w[open closed], ["open"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(%w[open closed], ["closed"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 6, rows[0].alert_number
              assert_equal 7, rows[1].alert_number
              assert_equal 8, rows[2].alert_number
              assert_equal 9, rows[3].alert_number
              assert_equal 10, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(["closed"], %w[open closed]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new(%w[open closed], ["open"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 5, rows.size
              assert_equal 1, rows[0].alert_number
              assert_equal 2, rows[1].alert_number
              assert_equal 3, rows[2].alert_number
              assert_equal 4, rows[3].alert_number
              assert_equal 5, rows[4].alert_number
            end
            assert_query_count(1) do
              ByState.new(%w[open closed], ["closed"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_equal 1, rows.size
              assert_equal 6, rows[0].alert_number
            end
            assert_query_count(1) do
              ByState.new(["closed"], %w[open closed]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
          end

          test "returns no results for conflicting filter values" do
            assert_query_count(1) do
              ByState.new(["open"], ["open"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
            assert_query_count(1) do
              ByState.new(["closed"], ["closed"]).apply(@dbot_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new(["open"], ["open"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
            assert_query_count(1) do
              ByState.new(["closed"], ["closed"]).apply(@cs_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end

            assert_query_count(1) do
              ByState.new(["open"], ["open"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
            assert_query_count(1) do
              ByState.new(["closed"], ["closed"]).apply(@ss_rel).to_a
            end.tap do |rows|
              assert_empty rows
            end
          end
        end
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByState.new([], []).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByState.new(["open"], []).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByState.new([], ["open"]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByState.new(["open"], ["closed"]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByState.new([], []).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByState.new(["open"], []).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByState.new([], ["open"]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByState.new(["open"], ["closed"]).has_incl_filters?
        end
      end
    end
  end
end
