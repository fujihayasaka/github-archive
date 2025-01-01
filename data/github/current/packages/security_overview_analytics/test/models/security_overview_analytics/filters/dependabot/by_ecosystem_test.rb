# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByEcosystemTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @rev_1 = create(:soa_dependabot_alert_revision, date_id: @date.id, ecosystem: "npm", alert_number: 1, repository: @repo.repository)
          @rev_2 = create(:soa_dependabot_alert_revision, date_id: @date.id, ecosystem: "maven", alert_number: 2, repository: @repo.repository)
          @rev_3 = create(:soa_dependabot_alert_revision, date_id: @date.id, ecosystem: "npm", alert_number: 3, repository: @repo.repository)
          @rev_4 = create(:soa_dependabot_alert_revision, date_id: @date.id, ecosystem: "RubyGems", alert_number: 4, repository: @repo.repository)
        end

        setup do
          @rev_rel = DependabotAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "returns the relation unchanged" do
              rel = ByEcosystem.new([], []).apply(@rev_rel)
              assert_equal(@rev_rel, rel)
            end
          end

          context "inclusive filters" do
            test "filters by ecosystem" do
              res = ByEcosystem.new(["npm"], []).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_1.ecosystem, @rev_3.ecosystem]
              assert_same_elements(expected, res)

              res = ByEcosystem.new(["maven"], []).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_2.ecosystem]
              assert_same_elements(expected, res)
            end

            test "filters by OR'd ecosystems with multiple filter values" do
              res = ByEcosystem.new(%w[npm RubyGems], []).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_1.ecosystem, @rev_3.ecosystem, @rev_4.ecosystem]
              assert_same_elements(expected, res)
            end
          end

          context "exclusive filters" do
            test "filters by ecosystem" do
              res = ByEcosystem.new([], ["npm"]).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_2.ecosystem, @rev_4.ecosystem]
              assert_same_elements(expected, res)

              res = ByEcosystem.new([], ["maven"]).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_1.ecosystem, @rev_3.ecosystem, @rev_4.ecosystem]
              assert_same_elements(expected, res)
            end

            test "filters by AND'd ecosystems with multiple filter values" do
              res = ByEcosystem.new([], %w[npm RubyGems]).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_2.ecosystem]
              assert_same_elements(expected, res)
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by OR'd inclusive ecosystems and AND'd exclusive ecosystems" do
              res = ByEcosystem.new(%w[npm RubyGems], ["npm"]).apply(@rev_rel).map(&:ecosystem)
              expected = [@rev_4.ecosystem]
              assert_same_elements(expected, res)

              res = ByEcosystem.new(["npm"], %w[npm RubyGems]).apply(@rev_rel).map(&:ecosystem)
              assert_empty(res)
            end

            test "returns no results for conflicting filter values" do
              res = ByEcosystem.new(["npm"], ["npm"]).apply(@rev_rel).map(&:ecosystem)
              assert_empty(res)
            end
          end
        end
      end
    end
  end
end
