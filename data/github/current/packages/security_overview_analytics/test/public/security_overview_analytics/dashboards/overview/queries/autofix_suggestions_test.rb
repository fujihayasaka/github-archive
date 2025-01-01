# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module Overview
      module Queries
        class AutofixSuggestionsTest < GitHub::TestCase
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business).tap do |business|
              @org1 = create(:organization, business:).tap do |owner|
                @repo_1 = create(:public_repository, owner:, name: "repo-1").tap do |repository|
                  create(:security_overview_analytics_repository, repository:)
                end
                @repo_2 = create(:private_repository, owner:, name: "repo-2").tap do |repository|
                  create(:security_overview_analytics_repository, repository:)
                end
              end

              @org2 = create(:organization, business:)
              @org3 = create(:organization, business:)
            end

            @org1_admin_user_session = create(:user_session, user: @org1.admin)
            @org2_admin_user_session = create(:user_session, user: @org2.admin)
            @org3_admin_user_session = create(:user_session, user: @org3.admin)

            @user_session = create(:user_session, user: @org1.admin)
          end

          setup do
            @end_date = ::Date.current
            @start_date = @end_date - 30.days
            SecurityOverviewAnalytics::FeatureFlagHelper.stubs(:use_alerts_filterer_class?).returns(true)
            ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
              .any_instance.stubs(:selected_backend_security_features)
              .returns(%w[dependabot_alerts secret_scanning codeql])
          end

          context "#perform" do
            context "when scope is an organization" do
              test "it forwards the single organization_id value to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    owner_ids: [@org1.id],
                    repository_ids: [],
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                result = new_query.perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end
            end

            context "when scope is a business" do
              test "it forwards the accessible organization_id values to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    owner_ids: [@org1.id, @org2.id],
                    repository_ids: [],
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                result = new_query(
                  scope: @biz,
                  authorized_orgs: [@org1, @org2],
                ).perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end

              test "it returns no results when no organizations are passed" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .never

                result = new_query(
                  scope: @biz,
                  authorized_orgs: []
                ).perform

                assert_instance_of(AutofixSuggestions::NoDataResult, result)
              end
            end

            context "when filtering by severity" do
              test "it forwards converted severity values to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    severities: [
                      :SEVERITY_CRITICAL,
                      :SEVERITY_HIGH,
                    ],
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                query = QueryParser.new("severity:critical,high")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end
            end

            context "when filtering by codeql rule" do
              test "it forwards rule sarif id values to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    rule_ids: [
                      "some/rule",
                      "another/rule",
                    ],
                    exclude_rule_ids: ["some/rule"],
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                query = QueryParser.new("codeql.rule:some/rule,another/rule -codeql.rule:some/rule")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end
            end

            context "when filtering with other tool-centric filters" do
              test "returns no-data if dependabot or secret scanning filters are applied" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .never

                query = QueryParser.new("secret-scanning.validity:active")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::NoDataResult, result)
              end

              test "returns no data if third-party rule filters are applied" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .never

                query = QueryParser.new("third-party.rule:rule/some-rule")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::NoDataResult, result)
              end
            end

            context "when filtering by repo attributes" do
              test "it forwards matching repository ids to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    repository_ids: [@repo_1.id]
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                query = QueryParser.new("repo:repo-1")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end

              test "it batches calls to turboscan if needed" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entry(repository_ids: [@repo_1.id]))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 12),
                  ))
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entry(repository_ids: [@repo_2.id]))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 34),
                  ))

                AutofixSuggestions.stub_const(:BATCH_SIZE, 1) do
                  query = QueryParser.new("archived:false")
                  result = new_query(query:).perform

                  assert_instance_of(AutofixSuggestions::Result, result)
                  result = T.let(result, AutofixSuggestions::Result)
                  assert_equal(46, result.suggestion_count)
                end
              end

              test "it returns no-data if no repos match" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .never

                query = QueryParser.new("repo:#{SecureRandom.uuid}")
                result = new_query(query:).perform

                assert_instance_of(AutofixSuggestions::NoDataResult, result)
              end
            end

            context "when user has limited repository access" do
              test "it forwards accessible repository ids to turboscan" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .with(has_entries(
                    owner_ids: [@org1.id],
                    repository_ids: [@repo_1.id]
                  ))
                  .returns(Twirp::ClientResp.new(
                    data: ::Turboscan::Proto::GetSuggestedFixStatisticsResponse.new(suggested: 42),
                  ))

                SecurityProduct::Permissions::OrgAuthz.any_instance.stubs(:can_manage_security_products?).returns(false)
                SecurityCenter::AuthorizationEnumerator
                  .any_instance
                  .expects(:allowed_repository_ids_by_feature_for_organization_member)
                  .returns({
                    "code_scanning" => [[@repo_1.id], false],
                  })

                result = new_query.perform

                assert_instance_of(AutofixSuggestions::Result, result)
                result = T.let(result, AutofixSuggestions::Result)
                assert_equal(42, result.suggestion_count)
              end
            end

            context "when codeql is not visible" do
              test "it returns a no-data result" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .never

                ::SecurityOverviewAnalytics::Dashboards::Overview::SecurityFeaturesParser
                  .any_instance.stubs(:selected_backend_security_features)
                  .returns([])

                result = new_query.perform

                assert_instance_of(AutofixSuggestions::NoDataResult, result)
              end
            end

            context "when turboscan returns an error" do
              test "it returns an error result" do
                ::GitHub::Turboscan::SuggestedFixes
                  .expects(:suggested_fix_statistics)
                  .returns(Twirp::ClientResp.new(error: Twirp::Error.unavailable("blip")))

                result = new_query.perform

                assert_instance_of(AutofixSuggestions::ErrorResult, result)
              end
            end
          end

          private

          def new_query(scope: @org1, **kwargs)
            if scope.is_a?(Organization)
              AutofixSuggestions.for_organization(
                organization: scope,
                user: @org1.admin,
                query: kwargs[:query] || QueryParser.new,
                start_date: kwargs[:start_date] || @start_date,
                end_date: kwargs[:end_date] || @end_date,
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
              )
            else
              AutofixSuggestions.for_business(
                business: scope,
                user: @org1.admin,
                query: kwargs[:query] || QueryParser.new,
                start_date: kwargs[:start_date] || @start_date,
                end_date: kwargs[:end_date] || @end_date,
                authorized_orgs: kwargs[:authorized_orgs] || scope.organizations.to_a,
                user_session: @user_session,
                return_alert_count: false,
                is_open_selected: true,
                slice4: nil
              )
            end
          end
        end
      end
    end
  end
end
