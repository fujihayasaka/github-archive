# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    class OrgReposFiltererTest < GitHub::TestCase
      QueryParser = ::Search::Queries::SecurityCenter::QueryParser

      fixtures do
        @user = create(:user)
        @user_session = create(:user_session, user: @user)
        @biz = create(:business, owners: [@user])
        @org = create(:organization, business: @biz, admin: @user)

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
          team.add_member(@user)
          team.add_repository(internal_repos[0], :admin)
          team.add_repository(private_repos[0], :admin)
        end

        @team_2 = create(:team, organization: @org, name: "Team 2").tap do |team|
          team.add_member(@user)
          team.add_repository(internal_repos[1], :admin)
          team.add_repository(private_repos[1], :admin)
        end
      end

      context "#cs_repo_metadata_rel" do
        context "when allowed_repo_ids is nil" do
          test "it returns a repo metadata relation for all repos in the org" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_equal(@internal_soa_repos.size + @private_soa_repos.size + @archived_soa_repos.size, rel.size)
          end
        end

        context "when allowed_repo_ids is not nil" do
          test "it returns a repo metadata relation for only the allowed repos" do
            allowed_repo_ids = @private_soa_repos.map(&:repository_id)

            rel = OrgReposFilterer
              .new(
                allowed_repo_ids_by_feature: { "code_scanning" => allowed_repo_ids },
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(allowed_repo_ids, rel.map(&:repository_id))
          end
        end

        context 'when querying by "archived"' do
          test "it returns only repos with the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:true"),
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(@archived_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end

          test "it returns only repos without the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:false"),
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(
              @internal_soa_repos.map(&:repository_id) + @private_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context "when querying by repo" do
          context 'with the "repo" qualifier' do
            test "it returns only repos containing the names" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new("repo:#{@internal_soa_repos[0].name},#{@private_soa_repos[0].name}"),
                  user: @user,
                  user_session: @user_session
                )
                .cs_repo_metadata_rel

              assert_same_elements(
                [
                  @internal_soa_repos[0].repository_id,
                  @private_soa_repos[0].repository_id
                ],
                rel.pluck(:repository_id)
              )
            end
          end

          context 'without the "repo" qualifier' do
            test "it returns only repos containing the name" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new(@private_soa_repos[1].name),
                  user: @user,
                  user_session: @user_session
                )
                .cs_repo_metadata_rel

              assert_same_elements(
                [@private_soa_repos[1].repository_id],
                rel.pluck(:repository_id)
              )
            end
          end
        end

        context 'when querying by "team"' do
          test "it returns only repos in the teams" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("team:#{@team_1.slug}"),
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(
              [
                @internal_soa_repos[0].repository_id,
                @private_soa_repos[0].repository_id
              ],
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "topic"' do
          test "it returns only repos with the topics" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("topic:#{@topic_private_repos}"),
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(
              @private_soa_repos.map(&:repository_id) + @archived_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "visibility"' do
          test "it returns only repos with the visibilities" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("visibility:#{@internal_soa_repos[0].visibility}"),
                user: @user,
                user_session: @user_session
              )
              .cs_repo_metadata_rel

            assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end
        end
      end

      context "#dbot_repo_metadata_rel" do
        context "when allowed_repo_ids is nil" do
          test "it returns a repo metadata relation for all repos in the org" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_equal(@internal_soa_repos.size + @private_soa_repos.size + @archived_soa_repos.size, rel.size)
          end
        end

        context "when allowed_repo_ids is not nil" do
          test "it returns a repo metadata relation for only the allowed repos" do
            allowed_repo_ids = @private_soa_repos.map(&:repository_id)

            rel = OrgReposFilterer
              .new(
                allowed_repo_ids_by_feature: { "dependabot_alerts" => allowed_repo_ids },
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(allowed_repo_ids, rel.map(&:repository_id))
          end
        end

        context 'when querying by "archived"' do
          test "it returns only repos with the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:true"),
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(@archived_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end

          test "it returns only repos without the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:false"),
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(
              @internal_soa_repos.map(&:repository_id) + @private_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context "when querying by repo" do
          context 'with the "repo" qualifier' do
            test "it returns only repos containing the names" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new("repo:#{@internal_soa_repos[0].name},#{@private_soa_repos[0].name}"),
                  user: @user,
                  user_session: @user_session
                )
                .dbot_repo_metadata_rel

              assert_same_elements(
                [
                  @internal_soa_repos[0].repository_id,
                  @private_soa_repos[0].repository_id
                ],
                rel.pluck(:repository_id)
              )
            end
          end

          context 'without the "repo" qualifier' do
            test "it returns only repos containing the name" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new(@private_soa_repos[1].name),
                  user: @user,
                  user_session: @user_session
                )
                .dbot_repo_metadata_rel

              assert_same_elements(
                [@private_soa_repos[1].repository_id],
                rel.pluck(:repository_id)
              )
            end
          end
        end

        context 'when querying by "team"' do
          test "it returns only repos in the teams" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("team:#{@team_1.slug}"),
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(
              [
                @internal_soa_repos[0].repository_id,
                @private_soa_repos[0].repository_id
              ],
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "topic"' do
          test "it returns only repos with the topics" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("topic:#{@topic_private_repos}"),
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(
              @private_soa_repos.map(&:repository_id) + @archived_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "visibility"' do
          test "it returns only repos with the visibilities" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("visibility:#{@internal_soa_repos[0].visibility}"),
                user: @user,
                user_session: @user_session
              )
              .dbot_repo_metadata_rel

            assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end
        end
      end

      context "#ss_repo_metadata_rel" do
        context "when allowed_repo_ids is nil" do
          test "it returns a repo metadata relation for all repos in the org" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_equal(@internal_soa_repos.size + @private_soa_repos.size + @archived_soa_repos.size, rel.size)
          end
        end

        context "when allowed_repo_ids is not nil" do
          test "it returns a repo metadata relation for only the allowed repos" do
            allowed_repo_ids = @private_soa_repos.map(&:repository_id)

            rel = OrgReposFilterer
              .new(
                allowed_repo_ids_by_feature: { "secret_scanning" => allowed_repo_ids },
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(allowed_repo_ids, rel.map(&:repository_id))
          end
        end

        context 'when querying by "archived"' do
          test "it returns only repos with the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:true"),
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(@archived_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end

          test "it returns only repos without the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:false"),
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(
              @internal_soa_repos.map(&:repository_id) + @private_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context "when querying by repo" do
          context 'with the "repo" qualifier' do
            test "it returns only repos containing the names" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new("repo:#{@internal_soa_repos[0].name},#{@private_soa_repos[0].name}"),
                  user: @user,
                  user_session: @user_session
                )
                .ss_repo_metadata_rel

              assert_same_elements(
                [
                  @internal_soa_repos[0].repository_id,
                  @private_soa_repos[0].repository_id
                ],
                rel.pluck(:repository_id)
              )
            end
          end

          context 'without the "repo" qualifier' do
            test "it returns only repos containing the name" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new(@private_soa_repos[1].name),
                  user: @user,
                  user_session: @user_session
                )
                .ss_repo_metadata_rel

              assert_same_elements(
                [@private_soa_repos[1].repository_id],
                rel.pluck(:repository_id)
              )
            end
          end
        end

        context 'when querying by "team"' do
          test "it returns only repos in the teams" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("team:#{@team_1.slug}"),
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(
              [
                @internal_soa_repos[0].repository_id,
                @private_soa_repos[0].repository_id
              ],
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "topic"' do
          test "it returns only repos with the topics" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("topic:#{@topic_private_repos}"),
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(
              @private_soa_repos.map(&:repository_id) + @archived_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "visibility"' do
          test "it returns only repos with the visibilities" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("visibility:#{@internal_soa_repos[0].visibility}"),
                user: @user,
                user_session: @user_session
              )
              .ss_repo_metadata_rel

            assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end
        end
      end

      context "#any_feature_repo_metadata_rel" do
        context "when allowed_repo_ids is nil" do
          test "it returns a repo metadata relation for all repos in the org" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_equal(@internal_soa_repos.size + @private_soa_repos.size + @archived_soa_repos.size, rel.size)
          end
        end

        context "when allowed_repo_ids is not nil" do
          test "it returns a repo metadata for combination of allowed repos" do
            allowed_repo_ids = @private_soa_repos.map(&:repository_id)

            rel = OrgReposFilterer
              .new(
                allowed_repo_ids_by_feature: { "code_scanning" => allowed_repo_ids[0..-2], "secret_scanning" => [allowed_repo_ids.last] },
                organization: @org,
                query: QueryParser.new,
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(allowed_repo_ids, rel.map(&:repository_id))
          end
        end

        context 'when querying by "archived"' do
          test "it returns only repos with the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:true"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(@archived_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end

          test "it returns only repos without the archived status" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("archived:false"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(
              @internal_soa_repos.map(&:repository_id) + @private_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context "when querying by repo" do
          context 'with the "repo" qualifier' do
            test "it returns only repos containing the names" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new("repo:#{@internal_soa_repos[0].name},#{@private_soa_repos[0].name}"),
                  user: @user,
                  user_session: @user_session
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(
                [
                  @internal_soa_repos[0].repository_id,
                  @private_soa_repos[0].repository_id
                ],
                rel.pluck(:repository_id)
              )
            end
          end

          context 'without the "repo" qualifier' do
            test "it returns only repos containing the name" do
              rel = OrgReposFilterer
                .new(
                  organization: @org,
                  query: QueryParser.new(@private_soa_repos[1].name),
                  user: @user,
                  user_session: @user_session
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(
                [@private_soa_repos[1].repository_id],
                rel.pluck(:repository_id)
              )
            end
          end
        end

        context 'when querying by "team"' do
          test "it returns only repos in the teams" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("team:#{@team_1.slug}"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(
              [
                @internal_soa_repos[0].repository_id,
                @private_soa_repos[0].repository_id
              ],
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "topic"' do
          test "it returns only repos with the topics" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("topic:#{@topic_private_repos}"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(
              @private_soa_repos.map(&:repository_id) + @archived_soa_repos.map(&:repository_id),
              rel.map(&:repository_id)
            )
          end
        end

        context 'when querying by "visibility"' do
          test "it returns only repos with the visibilities" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("visibility:#{@internal_soa_repos[0].visibility}"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end

          test "it supports `is` as a qualifier alias" do
            rel = OrgReposFilterer
              .new(
                organization: @org,
                query: QueryParser.new("is:#{@internal_soa_repos[0].visibility}"),
                user: @user,
                user_session: @user_session
              )
              .any_feature_repo_metadata_rel

            assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
          end
        end
      end
    end
  end
end
