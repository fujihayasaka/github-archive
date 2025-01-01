# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByOrganizationTest < GitHub::TestCase
      fixtures do
        @org1 = create(:organization, name: "test-org-1").tap do |owner|
          create_repo(owner:)
          create_repo(owner:)
        end

        @org2 = create(:organization, name: "test-org-2").tap do |owner|
          create_repo(owner:)
        end
      end

      test "applies positive filters" do
        filter = ByOrganization.new([@org1.display_login], [], authorized_orgs: [@org1, @org2])
        assert_same_elements repo_ids_for_orgs(@org1), filter.apply(Repository.all).pluck(:repository_id)

        refute_equal @org1.display_login, @org1.display_login.upcase
        filter = ByOrganization.new([@org1.display_login.upcase], [], authorized_orgs: [@org1, @org2]) # Filtering by different casing
        assert_same_elements repo_ids_for_orgs(@org1), filter.apply(Repository.all).pluck(:repository_id)

        filter = ByOrganization.new([@org1, @org2].map(&:display_login), [], authorized_orgs: [@org1, @org2])
        assert_same_elements repo_ids_for_orgs(@org1, @org2), filter.apply(Repository.all).pluck(:repository_id)

        filter = ByOrganization.new(["unknown"], [], authorized_orgs: [@org1, @org2])
        assert_empty filter.apply(Repository.all).pluck(:repository_id)
      end

      test "applies negated filters" do
        filter = ByOrganization.new([], [@org1.display_login], authorized_orgs: [@org1, @org2])
        assert_same_elements repo_ids_for_orgs(@org2), filter.apply(Repository.all).pluck(:repository_id)

        refute_equal @org1.display_login, @org1.display_login.upcase
        filter = ByOrganization.new([], [@org1.display_login.upcase], authorized_orgs: [@org1, @org2]) # Filtering by different casing
        assert_same_elements repo_ids_for_orgs(@org2), filter.apply(Repository.all).pluck(:repository_id)

        filter = ByOrganization.new([], [@org1, @org2].map(&:display_login), authorized_orgs: [@org1, @org2])
        assert_empty filter.apply(Repository.all).pluck(:repository_id)

        filter = ByOrganization.new([], ["unknown"], authorized_orgs: [@org1, @org2])
        assert_same_elements repo_ids_for_orgs(@org1, @org2), filter.apply(Repository.all).pluck(:repository_id)
      end

      test "applies both negated and positive filters" do
        filter = ByOrganization.new([@org2.display_login], [@org1.display_login], authorized_orgs: [@org1, @org2])
        assert_same_elements repo_ids_for_orgs(@org2), filter.apply(Repository.all).pluck(:repository_id)

        filter = ByOrganization.new([@org2.display_login], [@org2.display_login], authorized_orgs: [@org1, @org2])
        assert_empty filter.apply(Repository.all).pluck(:repository_id)
      end

      context "#is_empty?" do
        test "returns 'true' when provided no filters" do
          assert ByOrganization.new([], [], authorized_orgs: [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided inclusive filters" do
          refute ByOrganization.new([@org1.display_login], [], authorized_orgs: [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByOrganization.new([], [@org1.display_login], authorized_orgs: [@org1, @org2]).is_empty?
        end

        test "returns 'false' when provided both inclusive and exclusive filters" do
          refute ByOrganization.new([@org1.display_login], [@org2.display_login], authorized_orgs: [@org1, @org2]).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns 'false' when provided no filters" do
          refute ByOrganization.new([], [], authorized_orgs: [@org1, @org2]).has_incl_filters?
        end

        test "returns 'true' when provided inclusive filters" do
          assert ByOrganization.new([@org1.display_login], [], authorized_orgs: [@org1, @org2]).has_incl_filters?
        end

        test "returns 'false' when provided exclusive filters" do
          refute ByOrganization.new([], [@org1.display_login], authorized_orgs: [@org1, @org2]).has_incl_filters?
        end

        test "returns 'true' when provided both inclusive and exclusive filters" do
          assert ByOrganization.new([@org1.display_login], [@org2.display_login], authorized_orgs: [@org1, @org2]).has_incl_filters?
        end
      end

      def create_repo(owner:)
        create(:private_repository, owner:).tap do |repository|
          create(:security_overview_analytics_repository, repository:)
        end
      end

      def repo_ids_for_orgs(*orgs)
        orgs.flat_map { |org| org.repositories.pluck(:id) }
      end
    end
  end
end
