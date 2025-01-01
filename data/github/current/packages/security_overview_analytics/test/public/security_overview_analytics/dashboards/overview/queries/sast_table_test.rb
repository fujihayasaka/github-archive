# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class SastTableTest < GitHub::TestCase
          class TurboscanGetAlertsResult < T::Struct
            const :data, T.nilable(Turboscan::Proto::RulesForOrgResponse)
            const :error, T.nilable(String)
          end

          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @user_session = create(:user_session, user: @org_admin)
            @org = create(:organization, business: @biz, admin: @org_admin)

            @date_range_length_days = 9
            @start_date = ::Date.new(2022, 1, 1)
            @end_date = @start_date + @date_range_length_days.days
            @start_date.freeze
            @end_date.freeze

            @repo_1 = create(:private_repository, owner: @org).tap do |repo|
              create(:security_overview_analytics_repository, repository: repo)
              FeatureStatusRevision.create!(
                repository_id: repo.id,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@start_date),
                next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
                advanced_security_enabled: true,
                code_scanning_enabled: true,
                dependabot_alerts_enabled: false,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: false
              )
            end
            @repo_2 = create(:private_repository, owner: @org).tap do |repo|
              create(:security_overview_analytics_repository, repository: repo)
              FeatureStatusRevision.create!(
                repository_id: repo.id,
                date_id: ::SecurityOverviewAnalytics::Date.id_from_date(@start_date),
                next_revision_date_id: ::SecurityOverviewAnalytics::Date::FUTURE_DATE_ID,
                advanced_security_enabled: true,
                code_scanning_enabled: true,
                dependabot_alerts_enabled: false,
                secret_scanning_enabled: false,
                secret_scanning_push_protection_enabled: false
              )
            end

            rule_sarif_identifiers = 10.times.map do |idx|
              "rule_sarif_identifier_#{idx}"
            end
            rule_sarif_identifiers.freeze

            third_party_rule_sarif_identifiers = 7.times.map do |idx|
              "third_party_rule_sarif_identifier_#{idx}"
            end
            third_party_rule_sarif_identifiers.freeze


            # Every 2 days, create 10 codeql alert revisions and 7 third-party tool revisions for each rule sarif identifier.
            idx = T.let(1, Integer)
            (@start_date..@end_date).step(2).each do |date|
              rule_sarif_identifiers.each_with_index do |rule_sarif_identifier, i|
                severity = i % 2 == 0 ? "critical" : "high"
                CodeScanningAlertRevision.upsert_revision(
                  SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
                    alert_id: idx,
                    alert_created_at: @start_date.to_time,
                    alert_updated_at: date.to_time,
                    alert_severity: severity,
                    tool: "CodeQL",
                    rule_sarif_identifier: rule_sarif_identifier,
                    language: "ruby",
                    alert_resolved: false
                  ),
                  repository_id: [@repo_1].sample.id,
                  alert_number: idx,
                )

                # One of rules will have two alerts, to test sorting by alert count.
                if idx == 5
                  idx += 1
                  CodeScanningAlertRevision.upsert_revision(
                    SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
                      alert_id: idx,
                      alert_created_at: @start_date.to_time,
                      alert_updated_at: date.to_time,
                      alert_severity: severity,
                      tool: "CodeQL",
                      rule_sarif_identifier: rule_sarif_identifier,
                      language: "ruby",
                      alert_resolved: false
                    ),
                    repository_id: [@repo_1].sample.id,
                    alert_number: idx,
                  )
                end

                idx += 1
              end

              third_party_rule_sarif_identifiers.each_with_index do |rule_sarif_identifier, i|
                severity = i % 2 == 0 ? "high" : "low"
                tool = ["Grype", "Some tool", "ESLint"][i % 3]

                CodeScanningAlertRevision.upsert_revision(
                  SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
                    alert_id: idx,
                    alert_created_at: @start_date.to_time,
                    alert_updated_at: date.to_time,
                    alert_severity: severity,
                    tool: T.must(tool),
                    rule_sarif_identifier: rule_sarif_identifier,
                    language: "ruby",
                    alert_resolved: false
                  ),
                  repository_id: [@repo_1].sample.id,
                  alert_number: idx,
                )
                idx += 1
              end
            end

            # Create one more rule sarif identifier and a CodeScanningAlertRevision for it within the date range.
            # This rule sarif identifier will not be in the top 10 most common rule sarif identifiers.
            @top_eleventh_rule_sarif_identifier = "rule_sarif_identifier_11"

            CodeScanningAlertRevision.upsert_revision(
              SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
                alert_id: idx,
                alert_created_at: @end_date.to_time,
                alert_updated_at: @end_date.to_time,
                alert_severity: "critical",
                tool: "CodeQL",
                rule_sarif_identifier: @top_eleventh_rule_sarif_identifier,
                language: "ruby",
                alert_resolved: false
              ),
              repository_id: @repo_1.id,
              alert_number: idx,
            )

            # Create revisions after the date range.
            # They will not affect the results.

            rule_sarif_identifiers = (11..20).map do |idx|
              "rule_sarif_identifier_#{idx}"
            end
            rule_sarif_identifiers.freeze

            (@end_date..(@end_date + 10.days)).step(2).each do |date|
              rule_sarif_identifiers.each do |rule_sarif_identifier|
                CodeScanningAlertRevision.upsert_revision(
                  SecurityOverviewAnalytics::CodeScanningAlertRevision::UpdatePayload.new(
                    alert_id: idx,
                    alert_created_at: @start_date.to_time,
                    alert_updated_at: date.to_time,
                    alert_severity: "critical",
                    tool: "CodeQL",
                    rule_sarif_identifier: rule_sarif_identifier,
                    language: "ruby",
                    alert_resolved: false
                  ),
                  repository_id: [@repo_1, @repo_2].sample.id,
                  alert_number: idx,
                )
                idx += 1
              end
            end
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)

            GitHub::Turboscan
              .stubs(:rules_for_org)
              .with(Turboscan::Proto::RulesForOrgRequest.new({
                filter: Turboscan::Proto::AlertsFilter.new({
                  rule_sarif_identifiers: %w[
                    rule_sarif_identifier_4
                    rule_sarif_identifier_0
                    rule_sarif_identifier_1
                    rule_sarif_identifier_2
                    rule_sarif_identifier_3
                    rule_sarif_identifier_5
                    rule_sarif_identifier_6
                    rule_sarif_identifier_7
                    rule_sarif_identifier_8
                    rule_sarif_identifier_9
                  ]
                }).to_h,
                owner_ids: [@org.id],
                repository_ids: [@repo_1.id]
              }).to_h)
              .returns(
                TurboscanGetAlertsResult.new({
                  data: Turboscan::Proto::RulesForOrgResponse.new({
                    rules: [
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_1", short_description: "Rule name 1", tags: ["tag1", "external/cwe/cwe-101"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_2", short_description: "Rule name 2", tags: ["tag1", "external/cwe/cwe-102"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_3", short_description: "Rule name 3", tags: ["tag1", "external/cwe/cwe-103"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_4", short_description: "Rule name 4", tags: ["tag1", "external/cwe/cwe-104"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_5", short_description: "Rule name 5", tags: ["tag1", "external/cwe/cwe-105"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_6", short_description: "Rule name 6", tags: ["tag1", "external/cwe/cwe-106"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_7", short_description: "Rule name 7", tags: ["tag1", "external/cwe/cwe-107"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_8", short_description: "Rule name 8", tags: ["tag1", "external/cwe/cwe-108"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_9", short_description: "Rule name 9", tags: ["tag1", "external/cwe/cwe-109"] })
                    ]
                  })
                })
              )
          end

          context "#perform" do
            context "when security_features does not include code scanning tools" do
              test "it returns an empty array" do
                GitHub::Turboscan.expects(:rules_for_org).never

                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_empty(res)
              end
            end

            context "when the Turboscan request fails" do
              test "it returns an empty array" do
                GitHub::Turboscan
                  .stubs(:rules_for_org)
                  .returns(TurboscanGetAlertsResult.new({ error: "error" }))

                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([SecurityFeaturesParser::TOOL_CODEQL])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_empty(res)
              end
            end

            context "when the Turboscan request does not include a rule SARIF ID" do
              test "it excludes that rule SARIF ID from the output" do
                # rule_sarif_identifier_9 is not in the response.
                GitHub::Turboscan
                  .stubs(:rules_for_org)
                  .with(Turboscan::Proto::RulesForOrgRequest.new({
                    owner_ids: [@org.id],
                    repository_ids: [@repo_1.id],
                    filter: Turboscan::Proto::AlertsFilter.new({ rule_sarif_identifiers: %w[
                      rule_sarif_identifier_4
                      rule_sarif_identifier_0
                      rule_sarif_identifier_1
                      rule_sarif_identifier_2
                      rule_sarif_identifier_3
                      rule_sarif_identifier_5
                      rule_sarif_identifier_6
                      rule_sarif_identifier_7
                      rule_sarif_identifier_8
                      rule_sarif_identifier_9
                    ] }).to_h
                  }).to_h)
                  .returns(
                    TurboscanGetAlertsResult.new({
                      data: Turboscan::Proto::RulesForOrgResponse.new({
                        rules: [
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_4", short_description: "Rule name 4", tags: ["tag1", "external/cwe/cwe-104"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_1", short_description: "Rule name 1", tags: ["tag1", "external/cwe/cwe-101"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_2", short_description: "Rule name 2", tags: ["tag1", "external/cwe/cwe-102"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_3", short_description: "Rule name 3", tags: ["tag1", "external/cwe/cwe-103"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_5", short_description: "Rule name 5", tags: ["tag1", "external/cwe/cwe-105"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_6", short_description: "Rule name 6", tags: ["tag1", "external/cwe/cwe-106"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_7", short_description: "Rule name 7", tags: ["tag1", "external/cwe/cwe-107"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_8", short_description: "Rule name 8", tags: ["tag1", "external/cwe/cwe-108"] })
                        ]
                      })
                    })
                  )

                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([SecurityFeaturesParser::TOOL_CODEQL])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new,
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(
                  [
                    SastTable::Result.new(count_open_alerts: 6, cwes: ["CWE-104"], name: "Rule name 4", rule_sarif_id: "rule_sarif_identifier_4", severity: "critical"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-100"], name: "Rule name 0", rule_sarif_id: "rule_sarif_identifier_0", severity: "critical"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-101"], name: "Rule name 1", rule_sarif_id: "rule_sarif_identifier_1", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-102"], name: "Rule name 2", rule_sarif_id: "rule_sarif_identifier_2", severity: "critical"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-103"], name: "Rule name 3", rule_sarif_id: "rule_sarif_identifier_3", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-105"], name: "Rule name 5", rule_sarif_id: "rule_sarif_identifier_5", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-106"], name: "Rule name 6", rule_sarif_id: "rule_sarif_identifier_6", severity: "critical"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-107"], name: "Rule name 7", rule_sarif_id: "rule_sarif_identifier_7", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-108"], name: "Rule name 8", rule_sarif_id: "rule_sarif_identifier_8", severity: "critical")
                  ],
                  res
                )
              end
            end

            test "it returns the rule SARIF ID and severity for the 10 most common codeql alerts for the organization" do
              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns([SecurityFeaturesParser::TOOL_CODEQL])

              res = SastTable.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: @start_date,
                end_date: @end_date,
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(
                [
                  SastTable::Result.new(count_open_alerts: 6, cwes: ["CWE-104"], name: "Rule name 4", rule_sarif_id: "rule_sarif_identifier_4", severity: "critical"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-100"], name: "Rule name 0", rule_sarif_id: "rule_sarif_identifier_0", severity: "critical"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-101"], name: "Rule name 1", rule_sarif_id: "rule_sarif_identifier_1", severity: "high"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-102"], name: "Rule name 2", rule_sarif_id: "rule_sarif_identifier_2", severity: "critical"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-103"], name: "Rule name 3", rule_sarif_id: "rule_sarif_identifier_3", severity: "high"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-105"], name: "Rule name 5", rule_sarif_id: "rule_sarif_identifier_5", severity: "high"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-106"], name: "Rule name 6", rule_sarif_id: "rule_sarif_identifier_6", severity: "critical"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-107"], name: "Rule name 7", rule_sarif_id: "rule_sarif_identifier_7", severity: "high"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-108"], name: "Rule name 8", rule_sarif_id: "rule_sarif_identifier_8", severity: "critical"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-109"], name: "Rule name 9", rule_sarif_id: "rule_sarif_identifier_9", severity: "high")
                ],
                res
              )
            end

            test "it returns the rule SARIF ID and severity for the 10 most common third-party alerts for the organization" do
              GitHub::Turboscan
              .stubs(:rules_for_org)
              .with(Turboscan::Proto::RulesForOrgRequest.new({
                filter: Turboscan::Proto::AlertsFilter.new({
                  rule_sarif_identifiers: %w[
                    third_party_rule_sarif_identifier_0
                    third_party_rule_sarif_identifier_2
                    third_party_rule_sarif_identifier_3
                    third_party_rule_sarif_identifier_5
                    third_party_rule_sarif_identifier_6
                  ]
                }).to_h,
                owner_ids: [@org.id],
                repository_ids: [@repo_1.id]
              }).to_h)
              .returns(
                TurboscanGetAlertsResult.new({
                  data: Turboscan::Proto::RulesForOrgResponse.new({
                    rules: [
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_2", short_description: "Rule name 2", tags: ["tag1", "external/cwe/cwe-102"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_3", short_description: "Rule name 3", tags: ["tag1", "external/cwe/cwe-103"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_5", short_description: "Rule name 5", tags: ["tag1", "external/cwe/cwe-105"] }),
                      Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_6", short_description: "Rule name 6", tags: ["tag1", "external/cwe/cwe-106"] }),
                    ]
                  })
                })
              )

              ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                .any_instance.stubs(:selected_backend_security_features)
                .returns(%w[Grype ESLint])

              res = SastTable.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new,
                start_date: @start_date,
                end_date: @end_date,
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(
                [
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-100"], name: "Rule name 0", rule_sarif_id: "third_party_rule_sarif_identifier_0", severity: "high"),
                  # Exclude "Rule name 1" because the tool is "Some tool"
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-102"], name: "Rule name 2", rule_sarif_id: "third_party_rule_sarif_identifier_2", severity: "high"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-103"], name: "Rule name 3", rule_sarif_id: "third_party_rule_sarif_identifier_3", severity: "low"),
                  # Exclude "Rule name 4" because the tool is "Some tool"
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-105"], name: "Rule name 5", rule_sarif_id: "third_party_rule_sarif_identifier_5", severity: "low"),
                  SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-106"], name: "Rule name 6", rule_sarif_id: "third_party_rule_sarif_identifier_6", severity: "high"),
                ],
                res
              )
            end

            context "when alert-centric filters are applied" do
              test "it returns an empty array when resolution filters are applied" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([SecurityFeaturesParser::TOOL_CODEQL])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("resolution:risk-accepted"),
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_empty(res)
              end

              test "it returns the rule SARIF ID and selected severities for the 10 most common code scanning alerts for the organization" do
                GitHub::Turboscan
                  .stubs(:rules_for_org)
                  .with(Turboscan::Proto::RulesForOrgRequest.new({
                    filter: Turboscan::Proto::AlertsFilter.new({
                      rule_sarif_identifiers: %w[
                        rule_sarif_identifier_1
                        rule_sarif_identifier_3
                        rule_sarif_identifier_5
                        rule_sarif_identifier_7
                        rule_sarif_identifier_9
                      ]
                    }).to_h,
                    owner_ids: [@org.id],
                    repository_ids: [@repo_1.id]
                  }).to_h)
                  .returns(
                    TurboscanGetAlertsResult.new({
                      data: Turboscan::Proto::RulesForOrgResponse.new({
                        rules: [
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_1", short_description: "Rule name 1", tags: ["tag1", "external/cwe/cwe-101"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_2", short_description: "Rule name 2", tags: ["tag1", "external/cwe/cwe-102"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_3", short_description: "Rule name 3", tags: ["tag1", "external/cwe/cwe-103"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_4", short_description: "Rule name 4", tags: ["tag1", "external/cwe/cwe-104"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_5", short_description: "Rule name 5", tags: ["tag1", "external/cwe/cwe-105"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_6", short_description: "Rule name 6", tags: ["tag1", "external/cwe/cwe-106"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_7", short_description: "Rule name 7", tags: ["tag1", "external/cwe/cwe-107"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_8", short_description: "Rule name 8", tags: ["tag1", "external/cwe/cwe-108"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_9", short_description: "Rule name 9", tags: ["tag1", "external/cwe/cwe-109"] })
                        ]
                      })
                    })
                  )

                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([SecurityFeaturesParser::TOOL_CODEQL])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:high"),
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(
                  [
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-101"], name: "Rule name 1", rule_sarif_id: "rule_sarif_identifier_1", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-103"], name: "Rule name 3", rule_sarif_id: "rule_sarif_identifier_3", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-105"], name: "Rule name 5", rule_sarif_id: "rule_sarif_identifier_5", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-107"], name: "Rule name 7", rule_sarif_id: "rule_sarif_identifier_7", severity: "high"),
                    SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-109"], name: "Rule name 9", rule_sarif_id: "rule_sarif_identifier_9", severity: "high")
                  ],
                  res
                )
              end
            end

            context "when tool-centric filters are applied" do
              context "code scanning filters" do
                test "it returns the rule SARIF ID and severity for the most common codeql alerts with selected rule ids" do
                  GitHub::Turboscan
                  .stubs(:rules_for_org)
                  .with(Turboscan::Proto::RulesForOrgRequest.new({
                    filter: Turboscan::Proto::AlertsFilter.new({
                      rule_sarif_identifiers: %w[
                        rule_sarif_identifier_0
                        rule_sarif_identifier_1
                      ]
                    }).to_h,
                    owner_ids: [@org.id],
                    repository_ids: [@repo_1.id]
                  }).to_h)
                  .returns(
                    TurboscanGetAlertsResult.new({
                      data: Turboscan::Proto::RulesForOrgResponse.new({
                        rules: [
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "rule_sarif_identifier_1", short_description: "Rule name 1", tags: ["tag1", "external/cwe/cwe-101"] }),
                        ]
                      })
                    })
                  )

                  ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                    .any_instance.stubs(:selected_backend_security_features)
                    .returns([SecurityFeaturesParser::TOOL_CODEQL])

                  res = SastTable.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("codeql.rule:rule_sarif_identifier_0,rule_sarif_identifier_1"),
                    start_date: @start_date,
                    end_date: @end_date,
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal(
                    [
                      SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-100"], name: "Rule name 0", rule_sarif_id: "rule_sarif_identifier_0", severity: "critical"),
                      SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-101"], name: "Rule name 1", rule_sarif_id: "rule_sarif_identifier_1", severity: "high"),
                    ],
                    res
                  )
                end

                test "it returns the rule SARIF ID and severity for the most common third-party alerts with selected rule ids" do
                  GitHub::Turboscan
                  .stubs(:rules_for_org)
                  .with(Turboscan::Proto::RulesForOrgRequest.new({
                    filter: Turboscan::Proto::AlertsFilter.new({
                      rule_sarif_identifiers: %w[
                        third_party_rule_sarif_identifier_0
                        third_party_rule_sarif_identifier_2
                      ]
                    }).to_h,
                    owner_ids: [@org.id],
                    repository_ids: [@repo_1.id]
                  }).to_h)
                  .returns(
                    TurboscanGetAlertsResult.new({
                      data: Turboscan::Proto::RulesForOrgResponse.new({
                        rules: [
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_0", short_description: "Rule name 0", tags: ["tag1", "external/cwe/cwe-100"] }),
                          Turboscan::Proto::OrgRule.new({ sarif_identifier: "third_party_rule_sarif_identifier_2", short_description: "Rule name 2", tags: ["tag1", "external/cwe/cwe-102"] }),
                        ]
                      })
                    })
                  )

                  ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                    .any_instance.stubs(:selected_backend_security_features)
                    .returns([%w[Grype ESLint]])

                  res = SastTable.for_organization(
                    organization: @org,
                    user: @org_admin,
                    query: QueryParser.new("third-party.rule:third_party_rule_sarif_identifier_0,third_party_rule_sarif_identifier_2"),
                    start_date: @start_date,
                    end_date: @end_date,
                    user_session: @user_session,
                    is_open_selected: true,
                  ).perform

                  assert_equal(
                    [
                      SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-100"], name: "Rule name 0", rule_sarif_id: "third_party_rule_sarif_identifier_0", severity: "high"),
                      # Exclude "Rule name 1" because the tool is "Some tool"
                      SastTable::Result.new(count_open_alerts: 5, cwes: ["CWE-102"], name: "Rule name 2", rule_sarif_id: "third_party_rule_sarif_identifier_2", severity: "high"),
                    ],
                    res
                  )
                end
              end

              test "it returns an empty array if non-code scanning filters are applied" do
                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([SecurityFeaturesParser::TOOL_CODEQL, ::SecurityCenter::SecurityFeatures::SECRET_SCANNING])

                res = SastTable.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("secret-scanning.validity:active"),
                  start_date: @start_date,
                  end_date: @end_date,
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_empty(res)
              end
            end
          end
        end
      end
    end
  end
end
