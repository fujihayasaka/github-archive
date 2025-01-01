# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByAdvisoryTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @ghsa_id_1 = "GHSA-1234-5678-0001"
          @ghsa_id_2 = "GHSA-1234-5678-0002"
          @ghsa_id_3 = "GHSA-1234-5678-0003"

          @rev_1 = create(:soa_dependabot_alert_revision, date_id: @date.id, ghsa_id: @ghsa_id_1, alert_number: 1, repository: @repo.repository)
          @rev_2 = create(:soa_dependabot_alert_revision, date_id: @date.id, ghsa_id: @ghsa_id_2, alert_number: 2, repository: @repo.repository)
          @rev_3 = create(:soa_dependabot_alert_revision, date_id: @date.id, ghsa_id: @ghsa_id_1, alert_number: 3, repository: @repo.repository)
          @rev_4 = create(:soa_dependabot_alert_revision, date_id: @date.id, ghsa_id: @ghsa_id_3, alert_number: 4, repository: @repo.repository)
        end

        setup do
          @rev_rel = DependabotAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "returns the relation unchanged" do
              rel = ByAdvisory.new([], []).apply(@rev_rel)
              assert_equal(@rev_rel, rel)
            end
          end

          context "inclusive filters" do
            test "filters by ghsa_id" do
              res = ByAdvisory.new([@ghsa_id_1], []).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_1.ghsa_id, @rev_3.ghsa_id]
              assert_same_elements(expected, res)

              res = ByAdvisory.new([@ghsa_id_2], []).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_2.ghsa_id]
              assert_same_elements(expected, res)
            end

            test "filters by OR'd ghsa_ids with multiple filter values" do
              res = ByAdvisory.new([@ghsa_id_1, @ghsa_id_3], []).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_1.ghsa_id, @rev_3.ghsa_id, @rev_4.ghsa_id]
              assert_same_elements(expected, res)
            end
          end

          context "exclusive filters" do
            test "filters by ghsa_id" do
              res = ByAdvisory.new([], [@ghsa_id_1]).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_2.ghsa_id, @rev_4.ghsa_id]
              assert_same_elements(expected, res)

              res = ByAdvisory.new([], [@ghsa_id_2]).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_1.ghsa_id, @rev_3.ghsa_id, @rev_4.ghsa_id]
              assert_same_elements(expected, res)
            end

            test "filters by AND'd ghsa_ids with multiple filter values" do
              res = ByAdvisory.new([], [@ghsa_id_1, @ghsa_id_3]).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_2.ghsa_id]
              assert_same_elements(expected, res)
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by OR'd inclusive ghsa_ids and AND'd exclusive ghsa_ids" do
              res = ByAdvisory.new([@ghsa_id_1, @ghsa_id_3], [@ghsa_id_1]).apply(@rev_rel).map(&:ghsa_id)
              expected = [@rev_4.ghsa_id]
              assert_same_elements(expected, res)

              res = ByAdvisory.new([@ghsa_id_1], [@ghsa_id_1, @ghsa_id_3]).apply(@rev_rel).map(&:ghsa_id)
              assert_empty(res)
            end

            test "returns no results for conflicting filter values" do
              res = ByAdvisory.new([@ghsa_id_1], [@ghsa_id_1]).apply(@rev_rel).map(&:ghsa_id)
              assert_empty(res)
            end
          end
        end
      end
    end
  end
end
