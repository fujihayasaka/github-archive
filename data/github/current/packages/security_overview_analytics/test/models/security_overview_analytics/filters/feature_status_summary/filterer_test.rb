# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module FeatureStatusSummary
      class FiltererTest < GitHub::TestCase

        fixtures do
          create(:soa_feature_status, advanced_security_status: "ENABLED")
          create(:soa_feature_status, dependabot_alerts_status: "ENABLED", dependabot_alerts_critical_count: 1)
          create(:soa_feature_status, code_scanning_alerts_status: "ENABLED", code_scanning_alerts_critical_count: 1)
          create(:soa_feature_status, secret_scanning_alerts_status: "ENABLED")
          create(:soa_feature_status, dependabot_security_updates_status: "ENABLED")
          create(:soa_feature_status, dependabot_version_updates_status: "ENABLED")
          create(:soa_feature_status, code_scanning_auto_codeql_status: "ENABLED")
          create(:soa_feature_status, code_scanning_pr_reviews_status: "ENABLED")
          create(:soa_feature_status, secret_scanning_push_protection_status: "ENABLED")
        end

        setup do
          @rel = Repository.joins(:feature_status_summary).all
        end

        context "#apply" do
          context "when no filters applied" do
            test "it returns expected repositories" do
              rel = new_filterer("").apply(@rel)

              assert_equal @rel.count, rel.count
            end
          end

          %w[
            advanced-security
            code-scanning-alerts
            code-scanning-pull-request-alerts
            code-scanning-default-setup
            dependabot-alerts
            dependabot-security-updates
            secret-scanning-alerts
            secret-scanning-push-protection
          ].each do |qualifier|
            context "when filtered by #{qualifier}" do
              test "returns expected count of enabled repositories" do
                rel = new_filterer("#{qualifier}:enabled").apply(@rel)
                assert_equal 1, rel.count
              end

              test "returns expected count of not enabled repositories" do
                rel = new_filterer("-#{qualifier}:enabled").apply(@rel)
                assert_equal @rel.count - 1, rel.count
              end
            end
          end

          context "when filtered by has-severity" do
            test "returns expected count of repositories with severity" do
              rel = new_filterer("has-severity:critical").apply(@rel)
              assert_equal 2, rel.count
            end

            test "returns expected count of repositories without severity" do
              rel = new_filterer("-has-severity:critical").apply(@rel)
              assert_equal @rel.count - 2, rel.count
            end
          end
        end

        private

        def new_filterer(query)
          Filterer.new(Search::Queries::SecurityCenter::QueryParser.new(query))
        end
      end
    end
  end
end
