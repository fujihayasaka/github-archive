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
        @user = create(:user, business: @biz)
        @biz.add_owner(@user, actor: nil)

        @org = create(:organization, business: @biz, admin: @user)

        @non_business_admin_user = create(:user, business: @biz)
        @org2 = create(:organization, business: @biz, admin: @non_business_admin_user)

        org_repos = create_list(:internal_repository, 2, owner: @org)
        @org_soa_repos = org_repos.map do |repo|
          create(:soa_repository, repository: repo)
        end

        user_repo = create(:internal_repository, owner: @user)
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
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @user,
              organizations: [@org]
            )
            .any_feature_repo_metadata_rel

          assert_equal(@org_soa_repos.count + 1, rel.size)
        end

        test "for enterprise security manager it returns a repo metadata relation for allowed orgs and all users in the business" do
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @enterprise_security_manager,
              organizations: [@org]
            )
            .any_feature_repo_metadata_rel

          assert_equal(@org_soa_repos.count + 1, rel.size)
        end

        test "for non business owner it returns a repo metadata relation for allowed orgs and does not return users repos" do
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @non_business_admin_user,
              organizations: [@org2]
            )
            .any_feature_repo_metadata_rel

          assert_equal(@org2.repositories.count, rel.size)
        end

        test "for business owner when no orgs are passed it returns a repo metadata relation for users but not orgs in the business" do
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @user,
              organizations: []
            )
            .any_feature_repo_metadata_rel

          assert_equal 1, rel.size
        end

        test "for enterprise security manager when no orgs are passed it returns a repo metadata relation for users but not orgs in the business" do
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @enterprise_security_manager,
              organizations: []
            )
            .any_feature_repo_metadata_rel

          assert_equal 1, rel.size
        end


        test "for non business owner when no orgs are passed it returns no org or user repos" do
          rel = EnterpriseReposFilterer
            .new(
              business: @biz,
              query: QueryParser.new,
              user: @non_business_admin_user,
              organizations: []
            )
            .any_feature_repo_metadata_rel

          assert_equal 0, rel.size
        end
      end
    end
  end
end
