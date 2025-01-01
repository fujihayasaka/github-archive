# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByPackageTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @rev_1 = create(:soa_dependabot_alert_revision, date_id: @date.id, package_name: "@owner/package1", alert_number: 1, repository: @repo.repository)
          @rev_2 = create(:soa_dependabot_alert_revision, date_id: @date.id, package_name: "fetch", alert_number: 2, repository: @repo.repository)
          @rev_3 = create(:soa_dependabot_alert_revision, date_id: @date.id, package_name: "@owner/package1", alert_number: 3, repository: @repo.repository)
          @rev_4 = create(:soa_dependabot_alert_revision, date_id: @date.id, package_name: "com.github:java-package", alert_number: 4, repository: @repo.repository)
        end

        setup do
          @rev_rel = DependabotAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "returns the relation unchanged" do
              rel = ByPackage.new([], []).apply(@rev_rel)
              assert_equal(@rev_rel, rel)
            end
          end

          context "inclusive filters" do
            test "filters by package_name" do
              res = ByPackage.new(["@owner/package1"], []).apply(@rev_rel).map(&:package_name)
              expected = [@rev_1.package_name, @rev_3.package_name]
              assert_same_elements(expected, res)

              res = ByPackage.new(["fetch"], []).apply(@rev_rel).map(&:package_name)
              expected = [@rev_2.package_name]
              assert_same_elements(expected, res)
            end

            test "filters by OR'd package_names with multiple filter values" do
              res = ByPackage.new(%w[@owner/package1 com.github:java-package], []).apply(@rev_rel).map(&:package_name)
              expected = [@rev_1.package_name, @rev_3.package_name, @rev_4.package_name]
              assert_same_elements(expected, res)
            end
          end

          context "exclusive filters" do
            test "filters by package_name" do
              res = ByPackage.new([], ["@owner/package1"]).apply(@rev_rel).map(&:package_name)
              expected = [@rev_2.package_name, @rev_4.package_name]
              assert_same_elements(expected, res)

              res = ByPackage.new([], ["fetch"]).apply(@rev_rel).map(&:package_name)
              expected = [@rev_1.package_name, @rev_3.package_name, @rev_4.package_name]
              assert_same_elements(expected, res)
            end

            test "filters by AND'd package_names with multiple filter values" do
              res = ByPackage.new([], %w[@owner/package1 com.github:java-package]).apply(@rev_rel).map(&:package_name)
              expected = [@rev_2.package_name]
              assert_same_elements(expected, res)
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by OR'd inclusive package_names and AND'd exclusive package_names" do
              res = ByPackage.new(%w[@owner/package1 com.github:java-package], ["@owner/package1"]).apply(@rev_rel).map(&:package_name)
              expected = [@rev_4.package_name]
              assert_same_elements(expected, res)

              res = ByPackage.new(["@owner/package1"], %w[@owner/package1 com.github:java-package]).apply(@rev_rel).map(&:package_name)
              assert_empty(res)
            end

            test "returns no results for conflicting filter values" do
              res = ByPackage.new(["@owner/package1"], ["@owner/package1"]).apply(@rev_rel).map(&:package_name)
              assert_empty(res)
            end
          end
        end
      end
    end
  end
end
