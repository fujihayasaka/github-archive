# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class ExportDataTest < GitHub::TestCase
          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql some-tool]
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @date = create(:security_overview_analytics_date)
            @team = create(:team, organization: @org, privacy: :closed)
            @repo = create(:private_repository, owner: @org).tap do |repo|
              repo_metadata = create(:security_overview_analytics_repository, repository: repo)
              create(:security_overview_analytics_feature_status_revision, date: @date, repository_metadata: repo_metadata, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
              @team.add_repository repo, :admin
              repo_metadata
            end

            @topic = create(:topic)
            create(:repository_topic, topic: @topic, repository: @repo)

            @fruit = create :custom_property_definition, property_name: "fruit", value_type: :string, source: @org
            @veggie = create :custom_property_definition, property_name: "veggie", value_type: :string, source: @org
            create :custom_property_value, definition: @fruit, target: @repo, value: "apple"
            create :custom_property_value, definition: @veggie, target: @repo, value: "broccoli"
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
          end

          context "#perform" do
            test "returns alert data" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns(%w[dependabot_alerts secret_scanning codeql])

              # 5 days old
              dd = create(:soa_dependabot_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              dd_latest = create(:soa_dependabot_alert_revision, date_id: 20230930, next_revision_date_id: 20231006, repository: @repo, alert_number: 1, alert_created_at: ::Date.new(2023, 9, 30))
              # 4 days old
              ss = create(:soa_secret_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              ss_latest = create(:soa_secret_scanning_alert_revision, date_id: 20231001, next_revision_date_id: 20231006, repository: @repo, alert_number: 2, alert_created_at: ::Date.new(2023, 10, 1))
              # 3 days old
              cs = create(:soa_code_scanning_alert_revision, date_id: 20230928, next_revision_date_id: 20230930, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))
              cs_latest = create(:soa_code_scanning_alert_revision, date_id: 20231002, next_revision_date_id: 20231006, repository: @repo, alert_number: 3, alert_created_at: ::Date.new(2023, 10, 2))

              data = ExportData.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_equal(3, data.count)

              row = data[0]
              assert_equal row["tool"], "CodeQL"
              assert_equal row["alert_severity"], cs_latest.alert_severity
              assert_nil row["alert_bypassed"]
              assert_nil row["alert_type"]
              assert_nil row["alert_type_provider"]
              assert_nil row["alert_validity"]
              assert_nil row["ghsa_id"]
              assert_nil row["ecosystem"]
              assert_nil row["package_name"]
              assert_nil row["dependency_scope"]
              assert_equal row["rule_sarif_identifier"], cs_latest.rule_sarif_identifier
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["archived"], 0
              assert_equal row["alert_number"], cs_latest.alert_number
              assert_equal row["alert_created_at"], cs_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]
              assert_equal row["teams"], [@team.name]
              assert_equal row["repo_properties"], { "fruit" => "apple", "veggie" => "broccoli" }
              assert_equal row["repo_topics"], [@topic.name]

              row = data[1]
              assert_equal row["tool"], "dependabot"
              assert_equal row["alert_severity"], dd.alert_severity
              assert_nil row["alert_bypassed"]
              assert_nil row["alert_type"]
              assert_nil row["alert_type_provider"]
              assert_nil row["alert_validity"]
              assert_equal row["ghsa_id"], dd_latest.ghsa_id
              assert_equal row["ecosystem"], dd_latest.ecosystem
              assert_equal row["package_name"], dd_latest.package_name
              assert_equal row["dependency_scope"], dd_latest.dependency_scope
              assert_nil row["rule_sarif_identifier"]
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["archived"], 0
              assert_equal row["alert_number"], dd_latest.alert_number
              assert_equal row["alert_created_at"], dd_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]
              assert_equal row["teams"], [@team.name]
              assert_equal row["repo_properties"], { "fruit" => "apple", "veggie" => "broccoli" }
              assert_equal row["repo_topics"], [@topic.name]

              row = data[2]
              assert_equal row["tool"], "secret-scanning"
              assert_equal row["alert_severity"], "critical"
              assert_equal row["alert_bypassed"], 0
              assert_equal row["alert_type"], ss_latest.alert_type
              assert_equal row["alert_type_provider"], ss_latest.alert_type_provider
              assert_equal row["alert_validity"], 0
              assert_nil row["ghsa_id"]
              assert_nil row["ecosystem"]
              assert_nil row["package_name"]
              assert_nil row["dependency_scope"]
              assert_nil row["rule_sarif_identifier"]
              assert_equal row["name"], @repo.name
              assert_equal row["visibility"], 1
              assert_equal row["archived"], 0
              assert_equal row["alert_number"], ss_latest.alert_number
              assert_equal row["alert_created_at"], ss_latest.alert_created_at
              assert_nil row["alert_resolved_at"]
              assert_nil row["alert_reopened_at"]
              assert_nil row["alert_resolution"]
              assert_equal row["teams"], [@team.name]
              assert_equal row["repo_properties"], { "fruit" => "apple", "veggie" => "broccoli" }
              assert_equal row["repo_topics"], [@topic.name]
            end
          end

          context "when no features are selected" do
            test "it returns an empty response" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([])

              data = ExportData.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                return_alert_count: true,
                is_open_selected: true,
              ).perform

              assert_equal(0, data.count)
            end
          end
        end
      end
    end
  end
end
