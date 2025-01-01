# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    module SecretScanning
      class ByTokenTypeSlugTest < GitHub::TestCase
        fixtures do
          @org = create(:business_plus_organization)
          @repo = create(:security_overview_analytics_repository)
          @repo.update(organization_id: @org.id)
          @date = create(:security_overview_analytics_date)

          @ss_1 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 1, alert_type_slug: "aws_secret_access_key", repository: @repo.repository)
          @ss_2 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 2, alert_type_slug: "github_personal_access_token", repository: @repo.repository)
          @ss_3 = create(:security_overview_analytics_secret_scanning_alert_revision, date_id: @date.id, alert_number: 3, alert_type_slug: "my_custom_pattern", repository: @repo.repository)
        end

        setup do
          @ss_rel = SecretScanningAlertRevision.where(next_revision_date_id: 99991231)
        end

        context "#apply" do
          context "no filters are provided" do
            test "does not filter on alert_type_slugs" do
              assert_query_count(1) do
                ByTokenTypeSlug.new([], []).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                assert_equal 3, alert_type_slugs.size
              end
            end
          end

          context "inclusive filters" do
            test "filters by token slug" do
              assert_query_count(1) do
                ByTokenTypeSlug.new(["aws_secret_access_key"], []).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_1.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end

              assert_query_count(1) do
                ByTokenTypeSlug.new(["github_personal_access_token"], []).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_2.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end
            end

            test "filters by OR'd token slugs with multiple filter values" do
              assert_query_count(1) do
                ByTokenTypeSlug.new(%w[github_personal_access_token my_custom_pattern], []).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_2.alert_type_slug, @ss_3.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end
            end
          end

          context "exclusive filters" do
            test "filters by token slug" do
              assert_query_count(1) do
                ByTokenTypeSlug.new([], ["aws_secret_access_key"]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_2.alert_type_slug, @ss_3.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end

              assert_query_count(1) do
                ByTokenTypeSlug.new([], ["github_personal_access_token"]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_1.alert_type_slug, @ss_3.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end
            end

            test "filters by AND'd token slugs with multiple filter values" do
              assert_query_count(1) do
                ByTokenTypeSlug.new([], %w[github_personal_access_token my_custom_pattern]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_1.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end
            end
          end

          context "inclusive and exclusive filters" do
            test "filters by token slug" do
              assert_query_count(1) do
                ByTokenTypeSlug.new(["aws_secret_access_key"], ["my_custom_pattern"]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_1.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end
            end

            test "filters by OR'd inclusive token slugs and AND'd exclusive token slugs" do
              assert_query_count(1) do
                ByTokenTypeSlug.new(%w[github_personal_access_token my_custom_pattern], ["my_custom_pattern"]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                expected = [@ss_2.alert_type_slug]
                assert_same_elements expected, alert_type_slugs
              end

              assert_query_count(1) do
                ByTokenTypeSlug.new(["my_custom_pattern"], %w[my_custom_pattern github_personal_access_token]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                assert_empty alert_type_slugs
              end
            end

            test "returns no results for conflicting filter values" do
              assert_query_count(1) do
                ByTokenTypeSlug.new(["my_custom_pattern"], ["my_custom_pattern"]).apply(@ss_rel).map(&:alert_type_slug)
              end.tap do |alert_type_slugs|
                assert_empty alert_type_slugs
              end
            end
          end
        end
      end
    end
  end
end
