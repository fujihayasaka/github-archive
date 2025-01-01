# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      class SecurityFeaturesParserTest < GitHub::TestCase
        include ::SecurityCenter::TestFixtures

        QueryParser = ::Search::Queries::SecurityCenter::QueryParser

        fixtures do
          create_business_level_fixtures
          @user = create(:user)

          # Slices are using floor(`updated_at`) to calculate, so adding a second to make sure they are in different slices
          # One slice ends up containing ["CodeQL", "Tool 1"] and the other ["Tool 1", "tool-2"]
          updated_at = Time.now
          updated_at_2 = updated_at + 1.second

          now = Time.now
          date = create(:soa_date, date_value: now)
          @repo_1 = create(:repository, owner: @org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date, code_scanning_enabled: true)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 1, tool: "CodeQL")
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 2, tool: "Tool 1", updated_at: updated_at_2)
          end
          @repo_2 = create(:repository, owner: @org).tap do |r|
            metadata = create(:soa_repository, repository: r)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date, code_scanning_enabled: true)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 2, tool: "tool-2", updated_at: updated_at_2)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 5, tool: "Tool 1", updated_at: updated_at) # check we return uniqe tools
            # test that we exclude non-security severities
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 3, tool: "tool-warning", alert_severity: "warning")
          end

          create(:repository, owner: @org2).tap do |r|
            metadata = create(:soa_repository, repository: r)
            create(:soa_feature_status_revision, repository_metadata: metadata, date: date, code_scanning_enabled: true)
            create(:soa_code_scanning_alert_revision, repository_metadata: metadata, date: date, alert_number: 4, tool: "tool-3")
          end
        end

        setup do
          ::SecurityCenter::SecurityFeatures
            .stubs(:visible_features)
            .with(@org)
            .returns([
              ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
              ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
              ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
            ])

          ::SecurityCenter::SecurityFeatures
            .stubs(:visible_features)
            .with(@org2)
            .returns([
              ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
              ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
            ])
        end

        context "#backend_to_frontend_tool_map" do
          test "it returns a mapping from the backend security features values to values used by the Security Overview Dashboard frontend" do
            obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

            assert_equal(
              {
                "dependabot_alerts" => "dependabot",
                "codeql" => "codeql",
                "secret_scanning" => "secret-scanning"
              },
              obj.backend_to_frontend_tool_map
            )
          end
        end

        context "#allowed_third_party_tools" do
          context "when scope is an organization" do
            test "it returns all available third-party tools with their original casing preserved" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                ["Tool 1", "tool-2"],
                obj.allowed_third_party_tools
              )
            end
          end

          context "when scope is a business" do
            test "it raises when authorized_orgs is nil" do
              assert_raises do
                SecurityFeaturesParser.new(query: QueryParser.new, scope: @business)
              end
              assert_raises do
                SecurityFeaturesParser.new(query: QueryParser.new, scope: @business, authorized_code_scanning_orgs: nil)
              end
            end

            test "it returns all available third-party tools with their original casing preserved for authorized orgs" do
              authorized_code_scanning_orgs = [@org]
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @business, allowed_code_scanning_repo_ids: nil, authorized_code_scanning_orgs:)

              assert_same_elements(
                ["Tool 1", "tool-2"],
                obj.allowed_third_party_tools
              )
            end

            test "it returns no third-party tools when an empty list of authorized orgs is provided" do
              authorized_code_scanning_orgs = []
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @business, allowed_code_scanning_repo_ids: nil, authorized_code_scanning_orgs:)

              assert_same_elements(
                [],
                obj.allowed_third_party_tools
              )
            end
          end

          context "when using sliced query" do
            test "it returns all available third-party tools" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                ["Tool 1", "tool-2"],
                obj.allowed_third_party_tools
              )
            end
          end

        end

        context "#selected_backend_security_features" do
          context "when 'tool' is not present in the query" do
            test "it returns all backend security features visible to the user" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                ["codeql", "dependabot_alerts", "secret_scanning", "tool 1", "tool-2"],
                obj.selected_backend_security_features
              )
            end

            test "it filters by tools in repos that the user has access to" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: [@repo_1.id])

              assert_same_elements(
                ["codeql", "dependabot_alerts", "secret_scanning", "tool 1"],
                obj.selected_backend_security_features
              )
            end
          end

          context "when 'tool' is present in the query" do
            test "it maps the 'github' grouping to the three GitHub tools" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new("tool:github"), scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                %w[codeql dependabot_alerts secret_scanning],
                obj.selected_backend_security_features
              )
            end

            test "it maps the 'third-party' grouping to all 3rd party tools" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new("tool:third-party"), scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                ["tool 1", "tool-2"],
                obj.selected_backend_security_features
              )
            end

            test "it doesn't return any third party tools if the value is -tool:third-party" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new("-tool:third-party,codeql"), scope: @org, allowed_code_scanning_repo_ids: nil)
              assert_same_elements(
                %w[dependabot_alerts secret_scanning],
                obj.selected_backend_security_features
              )

              obj = SecurityFeaturesParser.new(query: QueryParser.new("tool:dependabot,tool-1 -tool:third-party"), scope: @org, allowed_code_scanning_repo_ids: nil)
              assert_same_elements(
                %w[dependabot_alerts],
                obj.selected_backend_security_features
              )
            end

            test "it doesn't return any github tools if the value is -tool:github" do
              obj = SecurityFeaturesParser.new(query: QueryParser.new("-tool:github"), scope: @org, allowed_code_scanning_repo_ids: nil)

              assert_same_elements(
                ["tool 1", "tool-2"],
                obj.selected_backend_security_features
              )
            end

            test "it returns the backend security features visible to the user that are also present in the query" do
              obj = SecurityFeaturesParser.new(
                query: QueryParser.new('tool:codeql,dependabot,"Tool 1"'),
                scope: @org,
                allowed_code_scanning_repo_ids: nil
              )

              assert_same_elements(
                ["codeql", "dependabot_alerts", "tool 1"],
                obj.selected_backend_security_features
              )
            end

            test "it applies case-insensitive filtering and returns the backend security features visible to the user that are also present in the query" do
              obj = SecurityFeaturesParser.new(
                query: QueryParser.new("tool:CODEQL,Dependabot,gRyPe"),
                scope: @org,
                allowed_code_scanning_repo_ids: nil
              )

              assert_same_elements(
                %w[codeql dependabot_alerts grype],
                obj.selected_backend_security_features
              )
            end
          end
        end

        context "#visible_backend_security_features" do
          test "it returns the backend security features visible to the user" do
            obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

            assert_same_elements(
              %w[codeql dependabot_alerts secret_scanning],
              obj.visible_backend_security_features
            )
          end
        end

        context "#visible_frontend_security_features" do
          test "it returns the frontend security features visible to the user" do
            obj = SecurityFeaturesParser.new(query: QueryParser.new, scope: @org, allowed_code_scanning_repo_ids: nil)

            assert_same_elements(
              %w[codeql dependabot secret-scanning],
              obj.visible_frontend_security_features
            )
          end
        end
      end
    end
  end
end
