# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByOwnerTypeTest < GitHub::TestCase
      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)

        @user1 = create(:user, business: @business, name: "test-user-1")
        @org1 = create(:organization, business: @business, name: "test-org-1", admin: @user1)

        @repo_a = create_repo("#{@org1}-repo-a", owner: @org1)
        @repo_b = create_repo("#{@org1}-repo-b", owner: @org1)
        @repo_c = create_repo("#{@org1}-repo-c", owner: @org1)

        @user_repo_a = create_repo("#{@user1}-repo-a", owner: @user1)
        @user_repo_b = create_repo("#{@user1}-repo-b", owner: @user1)
        @user_repo_c = create_repo("#{@user1}-repo-c", owner: @user1)

        @user2 = create(:user, business: @business, name: "test-user-2")
        @org2 = create(:organization, business: @business, name: "test-org-2", admin: @user2)

        @repo_d = create_repo("#{@org2}-repo-d", owner: @org2)
        @repo_e = create_repo("#{@org2}-repo-e", owner: @org2)
        @repo_f = create_repo("#{@org2}-repo-f", owner: @org2)

        @user_repo_d = create_repo("#{@user2}-repo-d", owner: @user2)
        @user_repo_e = create_repo("#{@user2}-repo-e", owner: @user2)
        @user_repo_f = create_repo("#{@user2}-repo-f", owner: @user2)
      end

      setup do
        Business.any_instance.stubs(:advanced_security_purchased?).returns(true)
        @base_rel = Repository.all
      end

      test "doesn't apply clause if no filters are provided" do
        rel = @base_rel.all
        expected_clause = rel.to_sql

        filter = ByOwnerType.new(nil, nil, @business, [@org1, @org2])
        assert_equal expected_clause, filter.apply(rel).to_sql

        filter = ByOwnerType.new([], [], @business, [@org1, @org2])
        assert_equal expected_clause, filter.apply(rel).to_sql
      end

      test "applies where clause with positive filters" do
        rel = @base_rel.all
        prefix_sql = rel.to_sql

        filter = ByOwnerType.new(%w[organization user], [], @business, [@org1, @org2])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `soa_repositories`.`owner_type` IN ('ORGANIZATION', 'USER')"
        else
          "WHERE `soa_repositories`.`owner_type` = 'ORGANIZATION'"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "applies where clause with negated filters" do
        rel = @base_rel.all
        prefix_sql = rel.to_sql

        filter = ByOwnerType.new([], %w[organization user], @business, [@org1, @org2])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `soa_repositories`.`owner_type` NOT IN ('ORGANIZATION', 'USER')"
        else
          "WHERE `soa_repositories`.`owner_type` != 'ORGANIZATION'"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "applies where clause with both negated and positive filters" do
        rel = @base_rel.all
        prefix_sql = rel.to_sql

        filter = ByOwnerType.new(%w[organization user], %w[organization user], @business, [@org1, @org2])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.enterprise?
          "WHERE `soa_repositories`.`owner_type` IN ('ORGANIZATION', 'USER') AND `soa_repositories`.`owner_type` NOT IN ('ORGANIZATION', 'USER')"
        else
          "WHERE `soa_repositories`.`owner_type` = 'ORGANIZATION' AND `soa_repositories`.`owner_type` != 'ORGANIZATION'"
        end
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "returns no results for unknown owner type" do
        rel = @base_rel.all
        prefix_sql = rel.to_sql

        filter = ByOwnerType.new(["unknown-owner-type"], [], @business, [@org1, @org2])
        expected_clause = "WHERE (1=0)"
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      test "returns results for negated unknown owner type" do
        rel = @base_rel.all
        prefix_sql = rel.to_sql

        filter = ByOwnerType.new([], ["unknown-owner-type"], @business, [@org1, @org2])
        expected_clause = "WHERE 1=1"
        assert_equal expected_clause, filter.apply(rel).to_sql.delete_prefix(prefix_sql).strip
      end

      context "user owned repositories" do
        test "returns included by owner type" do
          skip unless TestEnv.test_with_all_emus? || GitHub.enterprise?

          feature = ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          @users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 100).to_a

          rel = @base_rel.all
          filter = ByOwnerType.new(["user"], [], @business, [@org1, @org2])
          owners = filter.apply(rel).map(&:owner_id).uniq

          assert_equal 2, owners.count
          assert owners.include?(@user1.id), "User 1 should have been included in the results"
          assert owners.include?(@user2.id), "User 2 should have been included in the results"
        end

        test "returns excluded by owner type" do
          feature = ::AdvancedSecurity::Features::Business::AdvancedSecurity.new(@business)
          @users = feature.list_enterprise_users_offset(offset_id: 0, per_page: 100).to_a

          rel = @base_rel.all
          filter = ByOwnerType.new([], ["user"], @business, [@org1, @org2])
          owners = filter.apply(rel).map(&:owner_id).uniq

          @users.map(&:id).each do |id|
            refute owners.include?(id), "User #{id} should not be included in the results"
          end
        end
      end

      context "org owned repositories" do
        test "returns included by owner type" do
          rel = @base_rel.all
          filter = ByOwnerType.new(["organization"], [], @business, [@org1, @org2])
          owners = filter.apply(rel).map(&:owner_id).uniq
          assert_same_elements [@org1.id, @org2.id], owners
        end

        test "returns excluded by owner type" do
          rel = @base_rel.all
          filter = ByOwnerType.new([], ["organization"], @business, [@org1, @org2])
          owners = filter.apply(rel).map(&:owner_id).uniq
          refute_same_elements [@org1.id, @org2.id], owners
        end
      end

      def create_repo(name, owner:)
        create(:private_repository, name: name, owner: owner).tap do |r|
          if owner.user? && owner.is_enterprise_managed?
            business_id = owner.enterprise_managed_business.id
          else
            business_id = r.business&.id
          end
          create(:security_overview_analytics_repository, repository: r, business_id: business_id)
        end
      end

      def repo_ids_for_owners(owners)
        owners.map { |owners| owners.repositories.map(&:id) }.flatten.sort
      end
    end
  end
end
