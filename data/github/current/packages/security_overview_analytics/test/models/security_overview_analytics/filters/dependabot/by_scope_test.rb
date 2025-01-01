# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module Dependabot
      class ByScopeTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @rev_1 = create(:soa_dependabot_alert_revision, date_id: @date.id, dependency_scope: "runtime", alert_number: 1, repository: @repo.repository)
          @rev_2 = create(:soa_dependabot_alert_revision, date_id: @date.id, dependency_scope: "development", alert_number: 2, repository: @repo.repository)
          @rev_3 = create(:soa_dependabot_alert_revision, date_id: @date.id, dependency_scope: "runtime", alert_number: 3, repository: @repo.repository)
        end

        setup do
          @base_rel = DependabotAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no values are provided" do
            test "returns the relation unchanged" do
              rel = ByScope.new([], []).apply(@base_rel)
              assert_equal(@base_rel, rel)
            end
          end

          context "inclusive values" do
            context "when there are no valid values" do
              test "returns an empty relation" do
                rel = ByScope.new(["scope_unknown"], []).apply(@base_rel)
                assert_equal(@base_rel.none, rel)
              end
            end

            test "filters by dependency_scope" do
              res = ByScope.new(["runtime"], []).apply(@base_rel).map(&:dependency_scope)
              expected = [@rev_1.dependency_scope, @rev_3.dependency_scope]
              assert_same_elements(expected, res)

              res = ByScope.new(["development"], []).apply(@base_rel).map(&:dependency_scope)
              expected = [@rev_2.dependency_scope]
              assert_same_elements(expected, res)
            end

            test "filters by OR'd dependency_scopes with multiple values" do
              res = ByScope.new(%w[runtime scope_unknown], []).apply(@base_rel).map(&:dependency_scope)
              expected = [@rev_1.dependency_scope, @rev_3.dependency_scope]
              assert_same_elements(expected, res)
            end
          end

          context "exclusive values" do
            context "when there are invalid values" do
              test "it returns the base relation" do
                rel = ByScope.new([], ["runtime", SecureRandom.uuid]).apply(@base_rel)
                assert_equal(@base_rel, rel)
              end
            end

            test "filters by dependency_scope" do
              res = ByScope.new([], ["runtime"]).apply(@base_rel).map(&:dependency_scope)
              expected = [@rev_2.dependency_scope]
              assert_same_elements(expected, res)

              res = ByScope.new([], ["development"]).apply(@base_rel).map(&:dependency_scope)
              expected = [@rev_1.dependency_scope, @rev_3.dependency_scope]
              assert_same_elements(expected, res)
            end

            test "filters by AND'd dependency_scopes with multiple values" do
              res = ByScope.new([], %w[runtime development]).apply(@base_rel).map(&:dependency_scope)
              assert_empty(res)
            end
          end

          context "inclusive and exclusive values" do
            test "returns no results for conflicting values" do
              res = ByScope.new(["runtime"], ["runtime"]).apply(@base_rel).map(&:dependency_scope)
              assert_empty(res)
            end
          end
        end
      end
    end
  end
end
