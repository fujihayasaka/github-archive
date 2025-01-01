# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
  module Filters
    class ByOwnerTest < GitHub::TestCase
      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        @user1 = create(:user, business: @business, name: "test-user-1")
        @org1 = create(:organization, business: @business, name: "test-org-1", admin: @user1)

        @repo_a = create_repo("#{@org}-repo-a", owner: @org1)
        @repo_b = create_repo("#{@org}-repo-b", owner: @org1)
        @repo_c = create_repo("#{@org}-repo-c", owner: @org1)

        @user_repo_a = create_repo("#{@user1}-repo-a", owner: @user1)
        @user_repo_b = create_repo("#{@user1}-repo-b", owner: @user1)
        @user_repo_c = create_repo("#{@user1}-repo-c", owner: @user1)

        @user2 = create(:user, business: @business, name: "test-user-2")
        @org2 = create(:organization, business: @business, name: "test-org-2", admin: @user2)

        @repo_d = create_repo("#{@org}-repo-d", owner: @org2)
        @repo_e = create_repo("#{@org}-repo-e", owner: @org2)
        @repo_f = create_repo("#{@org}-repo-f", owner: @org2)

        @user_repo_d = create_repo("#{@user2}-repo-d", owner: @user2)
        @user_repo_e = create_repo("#{@user2}-repo-e", owner: @user2)
        @user_repo_f = create_repo("#{@user2}-repo-f", owner: @user2)
      end

      setup do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
      end

      test "doesn't apply clause if no filters are provided" do
        rel = RepositorySecurityCenterConfig.all
        expected_clause = rel.to_sql

        filter = ByOwner.new(nil, nil, @business)
        assert_equal expected_clause, filter.apply(rel).to_sql

        filter = ByOwner.new([], [], @business)
        assert_equal expected_clause, filter.apply(rel).to_sql
      end

      test "applies where clause with positive filters" do
        rel = RepositorySecurityCenterConfig.all
        prefix_sql = rel.to_sql

        filter = ByOwner.new([@org1.display_login, @user1.display_login], [], @business)
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `repository_security_center_configs`.`owner_id` IN (#{@org1.id}, #{@user1.id})"
        else
          "WHERE `repository_security_center_configs`.`owner_id` = #{@org1.id}"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "applies where clause with negated filters" do
        rel = RepositorySecurityCenterConfig.all
        prefix_sql = rel.to_sql

        filter = ByOwner.new([], [@org1.display_login, @user1.display_login], @business)
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `repository_security_center_configs`.`owner_id` NOT IN (#{@org1.id}, #{@user1.id})"
        else
          "WHERE `repository_security_center_configs`.`owner_id` != #{@org1.id}"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "applies where clause with both negated and positive filters" do
        rel = RepositorySecurityCenterConfig.all
        prefix_sql = rel.to_sql

        filter = ByOwner.new([@org1.display_login, @user1.display_login], [@org1.display_login, @user1.display_login], @business)
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `repository_security_center_configs`.`owner_id` IN (#{@org1.id}, #{@user1.id}) AND `repository_security_center_configs`.`owner_id` NOT IN (#{@org1.id}, #{@user1.id})"
        else
          "WHERE `repository_security_center_configs`.`owner_id` = #{@org1.id} AND `repository_security_center_configs`.`owner_id` != #{@org1.id}"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "returns no results for unknown owner" do
        rel = RepositorySecurityCenterConfig.all
        prefix_sql = rel.to_sql

        filter = ByOwner.new(["unknown-owner"], [], @business)
        expected_clause = "WHERE 1=0"
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      def create_repo(name, owner:)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )
        end
      end
    end
  end
end
