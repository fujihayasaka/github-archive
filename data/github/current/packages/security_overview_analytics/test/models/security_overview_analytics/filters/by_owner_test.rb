# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByOwnerTest < GitHub::TestCase
      fixtures do
        GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?
        @business = create(:global_business)
        @business2 = create(:global_business)

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
        @base_rel = Repository.all
      end

      test "doesn't apply clause if no filters are provided" do
        expected_clause = @base_rel.to_sql

        filter = ByOwner.new([], [], @business, [@org1, @org2, @user1])
        assert_equal expected_clause, filter.apply(@base_rel).to_sql
      end

      test "applies where clause with positive filters" do
        prefix_sql = @base_rel.to_sql

        filter = ByOwner.new([@org1.display_login, @user1.display_login], [], @business, [@org1, @org2])
        expected_repo_ids = repo_ids_for_owners([@org1])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.single_business_environment?
          expected_repo_ids = repo_ids_for_owners([@org1, @user1])
          "WHERE `soa_repositories`.`owner_id` IN (#{@org1.id}, #{@user1.id})"
        else
          # In non-emu case we are not using getting EMU users during filter generation
          "WHERE `soa_repositories`.`owner_id` = #{@org1.id}"
        end

        assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        assert_equal expected_repo_ids, filter.apply(@base_rel).to_a.map(&:id).sort
      end

      test "applies where clause with negated filters" do
        prefix_sql = @base_rel.to_sql

        filter = ByOwner.new([], [@org1.display_login, @user1.display_login], @business, [@org1, @org2])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.single_business_environment?
          expected_repo_ids = repo_ids_for_owners([@org2, @user2])
          "WHERE `soa_repositories`.`owner_id` NOT IN (#{@org1.id}, #{@user1.id})" \
        else
          # In non-emu case we are not using getting EMU users during filter generation
          # so even if we negate a user the filter won't apply and we get repos for all users
          expected_repo_ids = repo_ids_for_owners([@org2, @user1, @user2])
          "WHERE `soa_repositories`.`owner_id` != #{@org1.id}" \
        end

        assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        assert_equal expected_repo_ids, filter.apply(@base_rel).to_a.map(&:id).sort
      end

      test "applies where clause with both negated and positive filters" do
        prefix_sql = @base_rel.to_sql

        filter = ByOwner.new([@org1.display_login, @user1.display_login], [@org1.display_login, @user1.display_login], @business, [@org1, @org2, @user1])
        expected_clause = if TestEnv.test_with_all_emus? || GitHub.single_business_environment?
          "WHERE `soa_repositories`.`owner_id` IN (#{@org1.id}, #{@user1.id}) AND `soa_repositories`.`owner_id` NOT IN (#{@org1.id}, #{@user1.id})"
        else
          "WHERE `soa_repositories`.`owner_id` = #{@org1.id} AND `soa_repositories`.`owner_id` != #{@org1.id}"
        end

        assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        assert_empty filter.apply(@base_rel).to_a
      end

      test "returns no results for unknown owner" do
        prefix_sql = @base_rel.to_sql

        filter = ByOwner.new(["unknown-owner"], [], @business, [@org1, @org2, @user1])
        expected_clause = "WHERE 1=0"
        assert_equal expected_clause, filter.apply(@base_rel).to_sql.delete_prefix(prefix_sql).strip
        assert_empty filter.apply(@base_rel).to_a
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByOwner.new([], [], @business, [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByOwner.new([@org1.display_login], [], @business, [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByOwner.new([], [@org1.display_login], @business, [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByOwner.new([@org1.display_login], [@org2.display_login], @business, [@org1, @org2]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByOwner.new([], [], @business, [@org1, @org2]).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByOwner.new([@org1.display_login], [], @business, [@org1, @org2]).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByOwner.new([], [@org1.display_login], @business, [@org1, @org2]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByOwner.new([@org1.display_login], [@org2.display_login], @business, [@org1, @org2]).has_incl_filters?
        end
      end

      def create_repo(name, owner:)
        create(:private_repository, name: name, owner: owner).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end

      def repo_ids_for_owners(owners)
        owners.map { |owners| owners.repositories.map(&:id) }.flatten.sort
      end
    end
  end
end
