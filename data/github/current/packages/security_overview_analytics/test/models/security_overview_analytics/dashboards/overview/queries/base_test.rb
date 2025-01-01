# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class BaseTest < GitHub::TestCase
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          class TestBase < Base
            RunQueryOutput = type_member { { fixed: Integer } }

            private

            sig { override.returns(RunQueryOutput) }
            def query
              10
            end

            sig { override.returns(String) }
            def union_all_fallback_sql
              "SELECT 0 WHERE FALSE"
            end

            sig do
              override.params(
                rel: ActiveRecord::Relation,
                repo_metadata_rel: ActiveRecord::Relation,
                table_name: String
              ).returns(ActiveRecord::Relation)
            end
            def common_clauses_rel(rel, repo_metadata_rel, table_name)
              rel
            end
          end

          VALID_SECURITY_FEATURES = %w[dependabot_alerts secret_scanning codeql]

          fixtures do
            @biz = create(:business)
            @org_admin = create(:user)
            @org = create(:organization, business: @biz, admin: @org_admin)
            @user_session = create(:user_session, user: @org_admin)
            @repo = create(:private_repository, owner: @org)
            @repo_metadata = create(:security_overview_analytics_repository, repository: @repo)
          end

          setup do
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_for_resolution?).returns(true)
          end

          context "for_organization" do
            test "does not call auth enumerator if user can manage security products" do
              SecurityCenter::FeatureFlagHelper.stubs(:allow_custom_role_view_all_permission_check?).returns(false)
              SecurityProduct::Permissions::OrgAuthz.any_instance.expects(:can_manage_security_products?).returns(true)
              SecurityCenter::AuthorizationEnumerator.any_instance.expects(:allowed_repository_ids_by_feature_for_organization_member).never

              res = TestBase.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("severity:low"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(10, res)
            end

            test "does not call auth enumerator if user can view all alerts" do
              SecurityCenter::FeatureFlagHelper.stubs(:allow_custom_role_view_all_permission_check?).returns(true)
              SecurityProduct::Permissions::OrgAuthz.any_instance.expects(:can_view_all_alerts?).returns(true)
              SecurityCenter::AuthorizationEnumerator.any_instance.expects(:allowed_repository_ids_by_feature_for_organization_member).never

              res = TestBase.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("severity:low"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(10, res)
            end

            test "calls auth enumerator if user cannot manage security products" do
              SecurityCenter::FeatureFlagHelper.stubs(:allow_custom_role_view_all_permission_check?).returns(false)
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
              SecurityCenter::AuthorizationEnumerator.any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [@org.repositories.map(&:id), false],
                  "dependabot_alerts" => [@org.repositories.map(&:id), false],
                  "secret_scanning" => [@org.repositories.map(&:id), false],
                })
                .once

              res = TestBase.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("severity:low"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(10, res)
            end

            test "calls auth enumerator if user cannot view all alerts" do
              SecurityCenter::FeatureFlagHelper.stubs(:allow_custom_role_view_all_permission_check?).returns(true)
              SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_view_all_alerts?).returns(false)
              SecurityCenter::AuthorizationEnumerator.any_instance
                .expects(:allowed_repository_ids_by_feature_for_organization_member)
                .returns({
                  "code_scanning" => [@org.repositories.map(&:id), false],
                  "dependabot_alerts" => [@org.repositories.map(&:id), false],
                  "secret_scanning" => [@org.repositories.map(&:id), false],
                })
                .once

              res = TestBase.for_organization(
                organization: @org,
                user: @org_admin,
                query: QueryParser.new("severity:low"),
                start_date: ::Date.new(2023, 10, 2),
                end_date: ::Date.new(2023, 10, 5),
                user_session: @user_session,
                is_open_selected: true,
              ).perform

              assert_equal(10, res)
            end

            context "#perform" do
              test "returns the result of the perform method" do
                res = TestBase.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:low"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                ).perform

                assert_equal(10, res)
              end
            end

            context "#repo_metadata_rels" do
              test "it has relations for all security features" do
                res = TestBase.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:low"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                )

                assert_same_elements(
                  [
                    ::SecurityCenter::SecurityFeatures::CODE_SCANNING,
                    ::SecurityCenter::SecurityFeatures::DEPENDABOT_ALERTS,
                    ::SecurityCenter::SecurityFeatures::SECRET_SCANNING
                  ],
                  res.send(:repo_metadata_rels).keys
                )
              end
            end

            context "alerts_filterer" do
              test "applies query from alerts_filterer" do
                res = TestBase.for_organization(
                  organization: @org,
                  user: @org_admin,
                  query: QueryParser.new("severity:low"),
                  start_date: ::Date.new(2023, 10, 2),
                  end_date: ::Date.new(2023, 10, 5),
                  user_session: @user_session,
                  is_open_selected: true,
                )

                assert_includes(res.send(:dependabot_alerts_rel).to_sql, "AND `soa_dependabot_alert_revisions`.`alert_severity` = 'low'")
              end
            end
          end
        end
      end
    end
  end
end
