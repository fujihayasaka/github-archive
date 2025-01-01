# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module QueryServices
    class SecretScanningMetricsTest < GitHub::TestCase
      QueryParser = ::Search::Queries::SecurityCenter::QueryParser
      MetricsService = ::SecretScanning::Services::MetricsService

      fixtures do
        @biz = if GitHub.enterprise?
          create(:global_business)
        else
          create(:business, :enterprise_managed)
        end

        @biz_owner = @biz.owners.first
        @biz_owner_session = create(:user_session, user: @biz_owner)

        @emu_user = if GitHub.enterprise?
          create(:user, business: @biz)
        else
          create(:emu, business: @biz)
        end
        emu_repos = create_list(:private_repository, 2, owner: @emu_user).map do |repo|
          create(:soa_repository, repository: repo)
        end

        @org_owner = create(:user)
        @org_owner_session = create(:user_session, user: @org_owner)

        @org = create(:organization, business: @biz, admin: @org_owner)
        @another_org = create(:organization, business: @biz, admin: @org_owner)

        @topic_internal_repos = create(:topic, name: "internal")
        @topic_private_repos = create(:topic, name: "private")

        internal_repos = create_list(:internal_repository, 2, owner: @org)
        private_repos = create_list(:private_repository, 3, owner: @org)
        archived_repos = create_list(:archived_repository, 4, public: false, owner: @org)

        @internal_soa_repos = internal_repos.map do |repo|
          create(:repository_topic, topic: @topic_internal_repos, repository: repo)
          create(:soa_repository, repository: repo)
        end
        @private_soa_repos = private_repos.map do |repo|
          create(:repository_topic, topic: @topic_private_repos, repository: repo)
          create(:soa_repository, repository: repo)
        end

        @archived_soa_repos = archived_repos.map do |repo|
          create(:repository_topic, topic: @topic_private_repos, repository: repo)
          create(:soa_repository, repository: repo)
        end

        @team_1 = create(:team, organization: @org, name: "Team 1").tap do |team|
          team.add_member(@org_owner)
          team.add_repository(internal_repos[0], :admin)
          team.add_repository(private_repos[0], :admin)
        end

        @team_2 = create(:team, organization: @org, name: "Team 2").tap do |team|
          team.add_member(@org_owner)
          team.add_repository(internal_repos[1], :admin)
          team.add_repository(private_repos[1], :admin)
        end

        enterprise_security_manager_team = create :enterprise_security_manager_team, business: @biz
        @enterprise_security_manager = create :user
        @org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
        enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
        @esm_session = create(:user_session, user: @enterprise_security_manager)
      end

      context "with organization scope" do
        context "#get_push_protection_metrics" do
          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_push_protection_metrics)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
                allowed_repo_ids: []
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanningMetrics::NoDataResponse)
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false])

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end

            test "it sets `repo_ids` in request input if no other repo filters" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true &&
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false])

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true"),
                allowed_repo_ids: [target_repo.id],
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_push_protection_metrics
              assert result.is_a?(SecretScanningMetrics::NoDataResponse)

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_push_protection_metrics
              assert result.is_a?(SecretScanningMetrics::NoDataResponse)
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false])

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics

              assert result.is_a?(SecretScanningMetrics::NoDataResponse)
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetrics)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetrics).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetrics).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetrics).total_block_count
            end
          end
        end

        context "#get_push_protection_metrics_for_repos" do
          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
                allowed_repo_ids: []
              ).get_push_protection_metrics_for_repos

              refute error
              assert result&.is_a?(SecretScanningMetrics::NoDataResponse)
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false])

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_push_protection_metrics_for_repos
              refute error
              assert result&.is_a?(SecretScanningMetrics::NoDataResponse)

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_push_protection_metrics_for_repos
              refute error
              assert result&.is_a?(SecretScanningMetrics::NoDataResponse)
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false])

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .never

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics_for_repos

              refute error
              assert result&.is_a?(SecretScanningMetrics::NoDataResponse)
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_push_protection_metrics_for_repos)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                  bypassed_alert_count: 1,
                  successful_block_count: 2,
                  total_block_count: 3
                ), false]).once

              result, error = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_push_protection_metrics_for_repos

              refute error
              assert result.is_a?(SecretScanning::Models::PushProtectionMetricsForRepos)
              assert_equal 1, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).bypassed_alert_count
              assert_equal 2, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).successful_block_count
              assert_equal 3, T.cast(result, SecretScanning::Models::PushProtectionMetricsForRepos).total_block_count
            end
          end
        end

        context "#get_block_counts_by_token_type" do
          context "when cursor is set" do
            test "it passes nil to API service if omitted" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |_, _, cursor, **_|
                  cursor.nil?
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_token_type
            end

            test "it passes cursor input to API service" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |_, _, cursor, **_|
                  cursor == "test_cursor"
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_token_type(cursor: "test_cursor")
            end
          end

          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_block_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: []
              ).get_block_counts_by_token_type

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_token_type
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_block_counts_by_token_type
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_block_counts_by_token_type
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_block_counts_by_token_type
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_block_counts_by_token_type
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_block_counts_by_token_type
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_block_counts_by_token_type
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_token_type

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_token_type
            end
          end
        end

        context "#get_block_counts_by_repo" do
          context "when cursor is set" do
            test "it passes nil to API service if omitted" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |_, _, cursor, **_|
                  cursor.nil?
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_repo
            end

            test "it passes cursor input to API service" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |_, _, cursor, **_|
                  cursor == "test_cursor"
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_repo(cursor: "test_cursor")
            end
          end

          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_block_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: []
              ).get_block_counts_by_repo

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_repo
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_block_counts_by_repo
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_block_counts_by_repo
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_block_counts_by_repo
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_block_counts_by_repo
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_block_counts_by_repo
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_block_counts_by_repo
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_block_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_repo

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_block_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_block_counts_by_repo
            end
          end
        end

        context "#get_bypass_counts_by_token_type" do
          context "when cursor is set" do
            test "it passes nil to API service if omitted" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |_, _, cursor, **_|
                  cursor.nil?
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_token_type
            end

            test "it passes cursor input to API service" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |_, _, cursor, **_|
                  cursor == "test_cursor"
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_token_type(cursor: "test_cursor")
            end
          end

          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: []
              ).get_bypass_counts_by_token_type

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_token_type
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_bypass_counts_by_token_type
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_bypass_counts_by_token_type
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_bypass_counts_by_token_type
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_bypass_counts_by_token_type
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_bypass_counts_by_token_type
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_bypass_counts_by_token_type
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_token_type

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_token_type)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_token_type
            end
          end
        end

        context "#get_bypass_counts_by_repo" do
          context "when cursor is set" do
            test "it passes nil to API service if omitted" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |_, _, cursor, **_|
                  cursor.nil?
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_repo
            end

            test "it passes cursor input to API service" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |_, _, cursor, **_|
                  cursor == "test_cursor"
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_repo(cursor: "test_cursor")
            end
          end

          context "when allowed_repo_ids is set" do
            test "it returns empty response if its empty" do
              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: []
              ).get_bypass_counts_by_repo

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end

            test "it sets `repo_ids`" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_repo
            end
          end

          context 'when querying by "archived"' do
            test "it sets `repos_in_archived_state` in request input if no other repo filters" do
              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repos_in_archived_state] == true
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true")
              ).get_bypass_counts_by_repo
            end

            test "it sets `repo_ids` in request input if there are other repo filters" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true repo:#{target_repo.name}")
              ).get_bypass_counts_by_repo
            end

            test "it returns empty response if excludes all archived stats" do
              target_repo = @archived_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-archived:true,false")
              ).get_bypass_counts_by_repo
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("archived:true -archived:true")
              ).get_bypass_counts_by_repo
              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by only negated filters" do
            test "it sets `exclude_repo_ids` in request input if no other repo filter or scope" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:exclude_repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}")
              ).get_bypass_counts_by_repo
            end

            test "it sets `repo_ids` with reduced scope from allow_repo_ids" do
              target_repo = @private_soa_repos.first
              exclude_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:repo_ids] == [target_repo.id]
                end.once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{exclude_repo.name}"),
                allowed_repo_ids: [target_repo.id, exclude_repo.id]
              ).get_bypass_counts_by_repo
            end

            test "it returns empty response if filters reduced entire list of allowed_repo_ids" do
              target_repo = @private_soa_repos.first

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .never

              result = SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("-repo:#{target_repo.name}"),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_repo

              assert_equal 0, result&.data&.size
              assert_nil result&.next_cursor
              assert_nil result&.previous_cursor
            end
          end

          context "when querying by secret scanning filters" do
            test "it sets token filters that are applied and ignores bypassed filter" do
              target_repo = @private_soa_repos.last

              MetricsService
                .expects(:get_bypass_counts_by_repo)
                .with do |*_, **kwargs|
                  kwargs[:token_filters] =
                    SecretScanning::Services::MetricsService::PushProtectionTokenFilters.new(
                      token_types: [],
                      exclude_token_types: ["amazon_access_key"],
                      token_providers: ["Amazon AWS"],
                      exclude_token_providers: [],
                      token_validities: [1],
                      exclude_token_validities: []
                    )
                end
                .once

              SecretScanningMetrics.new(
                scope: @org,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new("secret-scanning.validity:active secret-scanning.provider:amazon_aws -secret-scanning.secret-type:amazon_access_key secret-scanning.bypassed:true"),
                allowed_repo_ids: [target_repo.id]
              ).get_bypass_counts_by_repo
            end
          end
        end
      end

      context "with business scope and business member" do
        context "#get_push_protection_metrics" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
              ).get_push_protection_metrics
            end
          end

          test "returns no-date response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new,
              authorized_orgs: []
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end
        end

        context "#get_push_protection_metrics_for_repos" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_push_protection_metrics_for_repos)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new,
              ).get_push_protection_metrics_for_repos
            end
          end

          test "returns no-date response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics_for_repos)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new,
              authorized_orgs: []
            ).get_push_protection_metrics_for_repos

            refute error
            assert result&.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_push_protection_metrics_for_repos)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end
              .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics_for_repos
          end
        end

        context "#get_block_counts_by_token_type" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_block_counts_by_token_type)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
              ).get_block_counts_by_token_type
            end
          end

          test "returns empty response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_block_counts_by_token_type)
              .never

            result = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new(""),
              authorized_orgs: []
            ).get_block_counts_by_token_type

            assert_equal 0, result&.data&.size
            assert_nil result&.next_cursor
            assert_nil result&.previous_cursor
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_block_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end.once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_token_type
          end
        end

        context "#get_block_counts_by_repo" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_block_counts_by_repo)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
              ).get_block_counts_by_repo
            end
          end

          test "returns empty response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_block_counts_by_repo)
              .never

            result = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new(""),
              authorized_orgs: []
            ).get_block_counts_by_repo

            assert_equal 0, result&.data&.size
            assert_nil result&.next_cursor
            assert_nil result&.previous_cursor
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_block_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end.once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_repo
          end
        end

        context "#get_bypass_counts_by_token_type" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_bypass_counts_by_token_type)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
              ).get_bypass_counts_by_token_type
            end
          end

          test "returns empty response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_bypass_counts_by_token_type)
              .never

            result = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new(""),
              authorized_orgs: []
            ).get_bypass_counts_by_token_type

            assert_equal 0, result&.data&.size
            assert_nil result&.next_cursor
            assert_nil result&.previous_cursor
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_bypass_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end.once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_token_type
          end
        end

        context "#get_bypass_counts_by_repo" do
          test "raises argument error if authorized_orgs not set" do
            MetricsService
              .expects(:get_bypass_counts_by_repo)
              .never

            assert_raises(ArgumentError) do
              result = SecretScanningMetrics.new(
                scope: @biz,
                user: @org_owner,
                user_session: @org_owner_session,
                query_parser: QueryParser.new(""),
              ).get_bypass_counts_by_repo
            end
          end

          test "returns empty response if authorized_orgs is empty" do
            MetricsService
              .expects(:get_bypass_counts_by_repo)
              .never

            result = SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new(""),
              authorized_orgs: []
            ).get_bypass_counts_by_repo

            assert_equal 0, result&.data&.size
            assert_nil result&.next_cursor
            assert_nil result&.previous_cursor
          end

          test "filters on organization owners" do
            MetricsService
              .expects(:get_bypass_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization
              end.once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @org_owner,
              user_session: @org_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_repo
          end
        end
      end

      context "with business scope and business owner" do
        context "#get_push_protection_metrics" do
          test "filters on all owner types as default" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new,
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on owners of all types" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on org owner" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.blank?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@org.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on user owner" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.blank? &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on user owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner-type:user"),
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on excluded owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("-owner-type:user"),
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on excluded owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].exclude_org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].exclude_user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("-owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on invalid owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:woof"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on invalid owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner-type:woof"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on conflicting incl and excl owner types" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner-type:user -owner-type:user"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on conflicting incl and excl owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login} -owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on user owners if authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: []
            ).get_push_protection_metrics
          end

          test "returns no-data response when forcing organization owner type while authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@org.display_login},#{@emu_user.display_login} owner-type:organization"),
              authorized_orgs: []
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end
        end

        context "#get_push_protection_metrics_for_repos" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_push_protection_metrics_for_repos)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics_for_repos
          end
        end

        context "#get_block_counts_by_token_type" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_block_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_token_type
          end
        end

        context "#get_block_counts_by_repo" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_block_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_repo
          end
        end

        context "#get_bypass_counts_by_token_type" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_bypass_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_token_type
          end
        end

        context "#get_bypass_counts_by_repo" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_bypass_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @biz_owner,
              user_session: @biz_owner_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_repo
          end
        end
      end

      context "with business scope and enterprise security manager" do
        context "#get_push_protection_metrics" do
          test "filters on all owner types as default" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new,
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on owners of all types" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on org owner" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.blank?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@org.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on user owner" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.blank? &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on user owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner-type:user"),
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on excluded owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Organization &&
                  kwargs[:repo_owners].org_ids == [@org.id] &&
                  kwargs[:repo_owners].user_ids.nil?
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("-owner-type:user"),
              authorized_orgs: [@org]
            ).get_push_protection_metrics
          end

          test "filters on excluded owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids.nil? &&
                  kwargs[:repo_owners].exclude_org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].exclude_user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("-owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics
          end

          test "filters on invalid owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:woof"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on invalid owner type" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner-type:woof"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on conflicting incl and excl owner types" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner-type:user -owner-type:user"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on conflicting incl and excl owners" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login} -owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end

          test "filters on user owners if authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::User &&
                  kwargs[:repo_owners].org_ids.nil? &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetrics.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: []
            ).get_push_protection_metrics
          end

          test "returns no-data response when forcing organization owner type while authorized_orgs is empty" do
            MetricsService
              .expects(:get_push_protection_metrics)
              .never

            result, error = SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@org.display_login},#{@emu_user.display_login} owner-type:organization"),
              authorized_orgs: []
            ).get_push_protection_metrics

            refute error
            assert result.is_a?(SecretScanningMetrics::NoDataResponse)
          end
        end

        context "#get_push_protection_metrics_for_repos" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_push_protection_metrics_for_repos)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .returns([::SecretScanning::Models::PushProtectionMetricsForRepos.new(
                bypassed_alert_count: 1,
                successful_block_count: 2,
                total_block_count: 3
              ), false]).once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_push_protection_metrics_for_repos
          end
        end

        context "#get_block_counts_by_token_type" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_block_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_token_type
          end
        end

        context "#get_block_counts_by_repo" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_block_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_block_counts_by_repo
          end
        end

        context "#get_bypass_counts_by_token_type" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_bypass_counts_by_token_type)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_token_type
          end
        end

        context "#get_bypass_counts_by_repo" do
          test "filters on all owner types" do
            MetricsService
              .expects(:get_bypass_counts_by_repo)
              .with do |*_, **kwargs|
                kwargs[:repo_owners].owner_type == MetricsService::RepoOwnerType::Any &&
                  kwargs[:repo_owners].org_ids == [@another_org.id] &&
                  kwargs[:repo_owners].user_ids == [@emu_user.id]
              end
              .once

            SecretScanningMetrics.new(
              scope: @biz,
              user: @enterprise_security_manager,
              user_session: @esm_session,
              query_parser: QueryParser.new("owner:#{@another_org.display_login},#{@emu_user.display_login}"),
              authorized_orgs: [@org, @another_org]
            ).get_bypass_counts_by_repo
          end
        end
      end
    end
  end
end
