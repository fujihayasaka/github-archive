# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    module EnablementTrends
      module Queries
        class EnablementTrendsChartTest < GitHub::TestCase
          QueryParser = ::Search::Queries::SecurityCenter::QueryParser

          fixtures do
            @biz = create(:business)
            @org = create(:organization, business: @biz)
            @org2 = create(:organization, business: @biz)

            @user = create(:user)
            @biz.add_owner(@user, actor: nil)

            @org.add_admin(@user)
            @org2.add_admin(@user)
            @user_session = create(:user_session, user: @user)

            @repo = create(:private_repository, owner: @org).tap do |repo|
              @repo_meta = create(:soa_repository, repository: repo, business_id: @biz.id)
            end

            @user_repo = create(:private_repository, owner: @user).tap do |repo|
              @user_repo_meta = create(:soa_repository, repository: repo, business_id: @biz.id)
            end

            @dates = ::Date.new(2024, 1, 1).upto(::Date.new(2024, 1, 10)).map do |date|
              create(:security_overview_analytics_date, id: Date.id_from_date(date), date_value: date)
            end
          end

          context "#perform" do
            test "returns an entry for each date in the range" do
              repos_filterer = OrgReposFilterer.new(
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              actual = EnablementTrendsChart.new(
                scope: @org,
                start_date: @dates.first.date_value,
                end_date: @dates.last.date_value,
                repos_filterer:,
                slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
              ).perform

              expected_dates = [
                ::Date.new(2024, 1, 1),
                ::Date.new(2024, 1, 2),
                ::Date.new(2024, 1, 3),
                ::Date.new(2024, 1, 4),
                ::Date.new(2024, 1, 5),
                ::Date.new(2024, 1, 6),
                # Jan 7 is removed via date sampling
                ::Date.new(2024, 1, 8),
                # Jan 9 is removed via date sampling
                ::Date.new(2024, 1, 10),
              ]
              expected = expected_dates.map do |date|
                EnablementTrendsChart::Result.new(date:)
              end

              assert_equal expected, actual
            end

            context "when scope is an organization" do
              test "returns the expected results" do
                feature_states = T.let({
                  dependabot_alerts_enabled: false,
                  dependabot_security_updates_enabled: false,
                  code_scanning_enabled: false,
                  code_scanning_pr_alerts_enabled: false,
                  secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: false,
                  advanced_security_enabled: false,
                }, T::Hash[Symbol, T::Boolean])

                # before query range, ghas enabled
                feature_states[:advanced_security_enabled] = true
                feature_states[:dependabot_alerts_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240101, next_revision_date_id: 20240103, **feature_states)

                # no events on 20240102

                # enable ghas features on 20240103
                feature_states[:code_scanning_enabled] = true
                feature_states[:secret_scanning_enabled] = true
                feature_states[:secret_scanning_push_protection_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240103, next_revision_date_id: 20240104, **feature_states)

                # "code scanning is too expensive, turn it off"
                feature_states[:code_scanning_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240104, next_revision_date_id: 20240106, **feature_states)

                # after query range, disable ghas
                feature_states[:advanced_security_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240106, next_revision_date_id: 99991231, **feature_states)

                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = [
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 2),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 0,
                    secret_scanning_push_protection_enabled: 0,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                    ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 3),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 1,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 4),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 5),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                ]

                assert_equal expected, actual
              end
            end

            context "when scope is a business" do
              context "when there are no authorized organizations" do
                test "returns default results" do
                  repos_filterer = EnterpriseReposFilterer.new(
                    business: @biz,
                    organizations: [],
                    query: QueryParser.new,
                    user: @user,
                  )
                  actual = EnablementTrendsChart.new(
                    scope: @biz,
                    start_date: ::Date.new(2024, 1, 2),
                    end_date: ::Date.new(2024, 1, 5),
                    repos_filterer:,
                    slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                  ).perform

                  expected = [
                    EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 2)),
                    EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 3)),
                    EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 4)),
                    EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 5)),
                  ]

                  assert_equal expected, actual
                end
              end

              test "returns the expected results for org-owned repositories" do
                feature_states = T.let({
                  dependabot_alerts_enabled: false,
                  dependabot_security_updates_enabled: false,
                  code_scanning_enabled: false,
                  code_scanning_pr_alerts_enabled: false,
                  secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: false,
                  advanced_security_enabled: false,
                }, T::Hash[Symbol, T::Boolean])

                # before query range, ghas enabled
                feature_states[:advanced_security_enabled] = true
                feature_states[:dependabot_alerts_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240101, next_revision_date_id: 20240103, **feature_states)

                # no events on 20240102

                # enable ghas features on 20240103
                feature_states[:code_scanning_enabled] = true
                feature_states[:secret_scanning_enabled] = true
                feature_states[:secret_scanning_push_protection_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240103, next_revision_date_id: 20240104, **feature_states)

                # "code scanning is too expensive, turn it off"
                feature_states[:code_scanning_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240104, next_revision_date_id: 20240106, **feature_states)

                # after query range, disable ghas
                feature_states[:advanced_security_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date_id: 20240106, next_revision_date_id: 99991231, **feature_states)

                repos_filterer = EnterpriseReposFilterer.new(
                  business: @biz,
                  organizations: @biz.organizations.to_a,
                  query: QueryParser.new,
                  user: @user,
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = [
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 2),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 0,
                    secret_scanning_push_protection_enabled: 0,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 3),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 1,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 4),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 5),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                ]

                assert_equal expected, actual
              end

              test "returns the expected results user-owned repositories" do
                ::AdvancedSecurity::Features::Business::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)

                feature_states = T.let({
                  dependabot_alerts_enabled: false,
                  dependabot_security_updates_enabled: false,
                  code_scanning_enabled: false,
                  code_scanning_pr_alerts_enabled: false,
                  secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: false,
                  advanced_security_enabled: false,
                }, T::Hash[Symbol, T::Boolean])

                # before query range, ghas enabled
                feature_states[:advanced_security_enabled] = true
                feature_states[:dependabot_alerts_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @user_repo_meta, date_id: 20240101, next_revision_date_id: 20240103, **feature_states)

                # no events on 20240102

                # enable ghas features on 20240103
                feature_states[:code_scanning_enabled] = true
                feature_states[:secret_scanning_enabled] = true
                feature_states[:secret_scanning_push_protection_enabled] = true
                create(:soa_feature_status_revision, repository_metadata: @user_repo_meta, date_id: 20240103, next_revision_date_id: 20240104, **feature_states)

                # "code scanning is too expensive, turn it off"
                feature_states[:code_scanning_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @user_repo_meta, date_id: 20240104, next_revision_date_id: 20240106, **feature_states)

                # after query range, disable ghas
                feature_states[:advanced_security_enabled] = false
                create(:soa_feature_status_revision, repository_metadata: @user_repo_meta, date_id: 20240106, next_revision_date_id: 99991231, **feature_states)

                repos_filterer = EnterpriseReposFilterer.new(
                  business: @biz,
                  organizations: @biz.organizations.to_a,
                  query: QueryParser.new,
                  user: @user,
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = [
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 2),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 0,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 0,
                    secret_scanning_push_protection_enabled: 0,
                    dependabot_alerts_repositories_count: 0,
                    dependabot_security_updates_repositories_count: 0,
                    code_scanning_repositories_count: 0,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 3),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 0,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 0,
                    dependabot_security_updates_repositories_count: 0,
                    code_scanning_repositories_count: 0,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 4),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 0,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 0,
                    dependabot_security_updates_repositories_count: 0,
                    code_scanning_repositories_count: 0,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 5),
                    total_repositories: 1,
                    dependabot_alerts_enabled: 0,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 0,
                    dependabot_security_updates_repositories_count: 0,
                    code_scanning_repositories_count: 0,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  ),
                ]

                assert_equal expected, actual
              end
            end

            context "when features are never enabled" do
              test "returns expected results" do
                # disabled before query range, never enabled
                create(:soa_feature_status_revision, repository_metadata: @repo_meta,
                  date: @dates.first,
                  dependabot_alerts_enabled: false,
                  dependabot_security_updates_enabled: false,
                  code_scanning_enabled: false,
                  code_scanning_pr_alerts_enabled: false,
                  secret_scanning_enabled: false,
                  secret_scanning_push_protection_enabled: false,
                  advanced_security_enabled: false,
                )

                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = ::Date.new(2024, 1, 2).upto(::Date.new(2024, 1, 5)).map do |date|
                  EnablementTrendsChart::Result.new(
                    date:,
                    total_repositories: 1,
                    dependabot_alerts_enabled: 0,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 0,
                    secret_scanning_enabled: 0,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  )
                end

                assert_equal expected, actual
              end
            end

            context "when features are never disabled" do
              test "returns expected results" do
                # enabled before query range, never disabled
                create(:soa_feature_status_revision, repository_metadata: @repo_meta, date: @dates.first,
                  dependabot_alerts_enabled: true,
                  dependabot_security_updates_enabled: true,
                  code_scanning_enabled: true,
                  code_scanning_pr_alerts_enabled: true,
                  secret_scanning_enabled: true,
                  secret_scanning_push_protection_enabled: true,
                  advanced_security_enabled: true,
                )

                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = ::Date.new(2024, 1, 2).upto(::Date.new(2024, 1, 5)).map do |date|
                  EnablementTrendsChart::Result.new(
                    date:,
                    total_repositories: 1,
                    dependabot_alerts_enabled: 1,
                    dependabot_security_updates_enabled: 1,
                    code_scanning_enabled: 1,
                    secret_scanning_enabled: 1,
                    secret_scanning_push_protection_enabled: 1,
                    dependabot_alerts_repositories_count: 1,
                    dependabot_security_updates_repositories_count: 1,
                    code_scanning_repositories_count: 1,
                    secret_scanning_repositories_count: 1,
                    secret_scanning_push_protection_repositories_count: 1,
                  )
                end

                assert_equal expected, actual
              end
            end

            context "when there are no feature status revisions" do
              test "returns default results" do
                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = ::Date.new(2024, 1, 2).upto(::Date.new(2024, 1, 5)).map do |date|
                  EnablementTrendsChart::Result.new(date:)
                end

                assert_equal expected, actual
              end
            end

            context "when there are no repositories" do
              test "returns default results" do
                org = create(:organization, business: @biz)
                org.add_admin(@user)
                # no repositories

                repos_filterer = OrgReposFilterer.new(
                  organization: org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: org,
                  start_date: ::Date.new(2024, 1, 2),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = [
                  EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 2)),
                  EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 3)),
                  EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 4)),
                  EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 5)),
                ]

                assert_equal expected, actual
              end
            end

            context "when single-date range is provided" do
              test "returns default results" do
                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 5),
                  end_date: ::Date.new(2024, 1, 5),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = [
                  EnablementTrendsChart::Result.new(date: ::Date.new(2024, 1, 5)),
                ]

                assert_equal expected, actual
              end
            end

            context "when inverted date range is provided" do
              test "returns empty array" do
                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )
                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 5),
                  end_date: ::Date.new(2024, 1, 4),
                  repos_filterer:,
                  slice_repositories: ::SecurityOverviewAnalytics::FeatureFlagHelper.enablement_trends_load_async?(@user),
                ).perform

                expected = []

                assert_equal expected, actual
              end
            end

            context "parallel queries using load_async" do
              test "returns the expected results" do
                # Create 2 repos in sequence, so they fall into 2 different slices
                # Create revisions on the same day, to test that we are aggregating the results correctly
                # Test is done in a transaction, so guaranteed not to be interleaved with other transactions
                repo1 = create(:private_repository, owner: @org)
                repo1_model = create(:soa_repository, repository: repo1)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo1_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                repo2 = create(:private_repository, owner: @org)
                repo2_model = create(:soa_repository, repository: repo2)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo2_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)
                repo3 = create(:private_repository, owner: @org)
                repo3_model = create(:soa_repository, repository: repo3)
                create(:security_overview_analytics_feature_status_revision, repository_metadata: repo3_model, date_id: 20231001, dependabot_alerts_enabled: true, code_scanning_enabled: true, secret_scanning_enabled: true, secret_scanning_push_protection_enabled: true, advanced_security_enabled: true)

                # Two days with same data
                expected = [
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 1),
                    total_repositories: 3,
                    dependabot_alerts_enabled: 3,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 3,
                    secret_scanning_enabled: 3,
                    secret_scanning_push_protection_enabled: 3,
                    dependabot_alerts_repositories_count: 3,
                    dependabot_security_updates_repositories_count: 3,
                    code_scanning_repositories_count: 3,
                    secret_scanning_repositories_count: 3,
                    secret_scanning_push_protection_repositories_count: 3,
                    ),
                  EnablementTrendsChart::Result.new(
                    date: ::Date.new(2024, 1, 2),
                    total_repositories: 3,
                    dependabot_alerts_enabled: 3,
                    dependabot_security_updates_enabled: 0,
                    code_scanning_enabled: 3,
                    secret_scanning_enabled: 3,
                    secret_scanning_push_protection_enabled: 3,
                    dependabot_alerts_repositories_count: 3,
                    dependabot_security_updates_repositories_count: 3,
                    code_scanning_repositories_count: 3,
                    secret_scanning_repositories_count: 3,
                    secret_scanning_push_protection_repositories_count: 3,
                  ),
                ]

                repos_filterer = OrgReposFilterer.new(
                  organization: @org,
                  query: QueryParser.new,
                  user: @user,
                  user_session: @user_session
                )

                actual = EnablementTrendsChart.new(
                  scope: @org,
                  start_date: ::Date.new(2024, 1, 1),
                  end_date: ::Date.new(2024, 1, 2),
                  repos_filterer:,
                  slice_repositories: true,
                ).perform

                assert_same_elements(expected, actual)
              end
            end
          end
        end
      end
    end
  end
end
