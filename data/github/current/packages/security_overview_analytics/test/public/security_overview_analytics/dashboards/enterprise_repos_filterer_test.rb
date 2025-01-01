# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Dashboards
    class EnterpriseReposFiltererTest < GitHub::TestCase
      QueryParser = ::Search::Queries::SecurityCenter::QueryParser

      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

        @biz = create(:global_business)
        @biz_admin_org_owner = create(:user, business: @biz)
        @biz.add_owner(@biz_admin_org_owner, actor: nil)

        @org = create(:organization, business: @biz, admin: @biz_admin_org_owner)

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
        @org_soa_repos = [@internal_soa_repos, @private_soa_repos, @archived_soa_repos].flatten

        @team_1 = create(:team, organization: @org, name: "Team 1").tap do |team|
          team.add_member(@biz_admin_org_owner)
          team.add_repository(internal_repos[0], :admin)
          team.add_repository(private_repos[0], :admin)
        end

        @team_2 = create(:team, organization: @org, name: "Team 2").tap do |team|
          team.add_member(@biz_admin_org_owner)
          team.add_repository(internal_repos[1], :admin)
          team.add_repository(private_repos[1], :admin)
        end

        @org2_owner = create(:user, business: @biz)
        @org2 = create(:organization, business: @biz, admin: @org2_owner)
        3.times { create(:repository, owner: @org2) }

        user_repo = create(:internal_repository, owner: @biz_admin_org_owner)
        @user_soa_repo = create(:soa_repository, repository: user_repo, business_id: @biz.id)

        enterprise_security_manager_team = create :enterprise_security_manager_team, business: @biz
        @enterprise_security_manager = create :user
        @org.add_member @enterprise_security_manager # Because the factory doesn't set up the org teams sync
        enterprise_security_manager_team.bulk_add_members(users: [@enterprise_security_manager])
      end

      setup do
        ::AdvancedSecurity::Features::Business::AdvancedSecurity.any_instance.stubs(:security_center_for_emus_enabled?).returns(true)
      end

      context "#any_feature_repo_metadata_rel" do
        test "for business owner it returns a repo metadata relation for allowed orgs and all users in the business" do
          [[@org], { my_action: [@org] }].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @biz_admin_org_owner,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal(@org_soa_repos.count + 1, rel.size)
          end
        end

        test "for enterprise security manager it returns a repo metadata relation for allowed orgs and all users in the business" do
          [[@org], { my_action: [@org] }].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @enterprise_security_manager,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal(@org_soa_repos.count + 1, rel.size)
          end
        end

        test "for non business owner it returns a repo metadata relation for allowed orgs and does not return users repos" do
          [[@org], { my_action: [@org] }].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @org2_owner,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal(@org_soa_repos.count, rel.size)
          end
        end

        test "for business owner when no orgs are passed it returns a repo metadata relation for users but not orgs in the business" do
          [[], {}].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @biz_admin_org_owner,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal 1, rel.size
          end
        end

        test "for enterprise security manager when no orgs are passed it returns a repo metadata relation for users but not orgs in the business" do
          [[], {}].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @enterprise_security_manager,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal 1, rel.size
          end
        end

        test "for non business owner when no orgs are passed it returns no org or user repos" do
          [[], {}].each do |organizations|
            rel = EnterpriseReposFilterer
              .new(
                business: @biz,
                query: QueryParser.new,
                user: @org2_owner,
                organizations:,
              )
              .any_feature_repo_metadata_rel

            assert_equal 0, rel.size
          end
        end

        context 'when querying by "archived"' do
          test "it returns only repos with the archived status" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("archived:true"),
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(@archived_soa_repos.map(&:repository_id), rel.map(&:repository_id))
            end
          end

          test "it returns only repos without the archived status" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("archived:false"),
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(
                [@internal_soa_repos, @private_soa_repos, @user_soa_repo].flatten.map(&:repository_id),
                rel.map(&:repository_id)
              )
            end
          end
        end

        context "when querying by repo" do
          context 'with the "repo" qualifier' do
            test "it returns only repos containing the names" do
              [[@org], { my_action: [@org] }].each do |organizations|
                rel = EnterpriseReposFilterer
                  .new(
                    business: @biz,
                    query: QueryParser.new("repo:#{@internal_soa_repos[0].name},#{@private_soa_repos[0].name}"),
                    user: @biz_admin_org_owner,
                    organizations:,
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
          end

          context 'without the "repo" qualifier' do
            test "it returns only repos containing the name" do
              [[@org], { my_action: [@org] }].each do |organizations|
                rel = EnterpriseReposFilterer
                  .new(
                    business: @biz,
                    query: QueryParser.new(@private_soa_repos[1].name),
                    user: @biz_admin_org_owner,
                    organizations:,
                  )
                  .any_feature_repo_metadata_rel

                assert_same_elements(
                  [@private_soa_repos[1].repository_id],
                  rel.pluck(:repository_id)
                )
              end
            end
          end
        end

        context 'when querying by "team"' do
          test "it returns only repos in the teams" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("team:#{@team_1.slug}"),
                  user: @biz_admin_org_owner,
                  organizations:,
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
        end

        context 'when querying by "topic"' do
          test "it returns only repos with the topics" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("topic:#{@topic_private_repos}"),
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(
                @private_soa_repos.map(&:repository_id) + @archived_soa_repos.map(&:repository_id),
                rel.map(&:repository_id)
              )
            end
          end
        end

        context 'when querying by "visibility"' do
          test "it returns only repos with the visibilities" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("visibility:#{@internal_soa_repos[0].visibility}"),
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
            end
          end

          test "it supports `is` as a qualifier alias" do
            [[@org], { my_action: [@org] }].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new("is:#{@internal_soa_repos[0].visibility}"),
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .any_feature_repo_metadata_rel

              assert_same_elements(@internal_soa_repos.map(&:repository_id), rel.map(&:repository_id))
            end
          end
        end
      end

      {
        cs_repo_metadata_rel: :read_code_scanning,
        dbot_repo_metadata_rel: :view_dependabot_alerts,
        ss_repo_metadata_rel: :view_secret_scanning_alerts,
      }.each do |method, fgp|
        context "##{method}" do
          test "raises error if missing associated action in organizations hash" do
            assert_raises(TypeError) do
              organizations_by_action = {
                read_code_scanning: [],
                view_dependabot_alerts: [],
                view_secret_scanning_alerts: [],
              }

              EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new,
                  user: @biz_admin_org_owner,
                  organizations: organizations_by_action.tap { |h| h.delete(fgp) },
                )
                .send(method)
            end
          end

          test "for business owner it returns a repo metadata relation for allowed orgs and all users in the business" do
            organizations_by_action = {
              read_code_scanning: [@org2],
              view_dependabot_alerts: [@org2],
              view_secret_scanning_alerts: [@org2],
            }.tap { |h| h[fgp] = [@org] }

            [[@org], organizations_by_action].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new,
                  user: @biz_admin_org_owner,
                  organizations:,
                )
                .send(method)

              assert_equal(@org_soa_repos.count + 1, rel.size)
            end
          end

          test "for security manager it returns a repo metadata relation for allowed orgs and all users in the business" do
            organizations_by_action = {
              read_code_scanning: [@org2],
              view_dependabot_alerts: [@org2],
              view_secret_scanning_alerts: [@org2],
            }.tap { |h| h[fgp] = [@org] }

            [[@org], organizations_by_action].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new,
                  user: @enterprise_security_manager,
                  organizations:,
                )
                .send(method)

              assert_equal(@org_soa_repos.count + 1, rel.size)
            end
          end

          test "for non business owner it returns a repo metadata relation for allowed orgs" do
            organizations_by_action = {
              read_code_scanning: [@org2],
              view_dependabot_alerts: [@org2],
              view_secret_scanning_alerts: [@org2],
            }.tap { |h| h[fgp] = [@org] }

            [[@org], organizations_by_action].each do |organizations|
              rel = EnterpriseReposFilterer
                .new(
                  business: @biz,
                  query: QueryParser.new,
                  user: @org2_owner,
                  organizations:,
                )
                .send(method)

              assert_equal(@org_soa_repos.count, rel.size)
            end
          end
        end
      end
    end
  end
end
