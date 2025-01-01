# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByTokenProviderTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @ss_1 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 1, alert_type_provider: "Amazon AWS", repository: @repo.repository)
          @ss_2 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 2, alert_type_provider: "GitHub", repository: @repo.repository)
          @ss_3 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 3, alert_type_provider: "", repository: @repo.repository)
        end

        setup do
          @ss_rel = SecretScanningAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "does not filter on alert_type_providers" do
              assert_query_count(1) do
                ByTokenProvider.new([], []).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                assert_equal 3, alert_type_providers.size
              end
            end
          end

          context "inclusive filters" do
            test "filters by token provider slug" do
              assert_query_count(1) do
                ByTokenProvider.new(["amazon_aws"], []).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_1.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end

              assert_query_count(1) do
                ByTokenProvider.new(["github"], []).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_2.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end

            test "filters are case-insensitive" do
              assert_query_count(1) do
                ByTokenProvider.new(["gItHuB"], []).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_2.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end

            test "filters by OR'd token providers with multiple filter values" do
              assert_query_count(1) do
                ByTokenProvider.new(%w[amazon_aws github], []).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_1.alert_type_provider, @ss_2.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end
          end

          context "exclusive filters" do
            test "filters by token provider slug" do
              assert_query_count(1) do
                ByTokenProvider.new([], ["amazon_aws"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_2.alert_type_provider, @ss_3.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end

              assert_query_count(1) do
                ByTokenProvider.new([], ["github"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_1.alert_type_provider, @ss_3.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end

            test "filters are case-insensitive" do
              assert_query_count(1) do
                ByTokenProvider.new([], ["gItHuB"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_1.alert_type_provider, @ss_3.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end

            test "filters by AND'd token providers with multiple filter values" do
              assert_query_count(1) do
                ByTokenProvider.new([], %w[amazon_aws github]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_3.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by token provider slug" do
              assert_query_count(1) do
                ByTokenProvider.new(["amazon_aws"], ["github"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_1.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end
            end

            test "filters by OR'd inclusive token providers and AND'd exclusive token providers" do
              assert_query_count(1) do
                ByTokenProvider.new(%w[github amazon_aws], ["amazon_aws"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                expected = [@ss_2.alert_type_provider]
                assert_same_elements expected, alert_type_providers
              end

              assert_query_count(1) do
                ByTokenProvider.new(["amazon_aws"], %w[amazon_aws github]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                assert_empty alert_type_providers
              end
            end

            test "returns no results for conflicting filter values" do
              assert_query_count(1) do
                ByTokenProvider.new(["github"], ["github"]).apply(@ss_rel).map(&:alert_type_provider)
              end.tap do |alert_type_providers|
                assert_empty alert_type_providers
              end
            end
          end
        end
      end
    end
  end
end
