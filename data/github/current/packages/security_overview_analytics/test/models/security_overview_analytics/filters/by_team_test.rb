# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  module Filters
    class ByTeamTest < GitHub::TestCase
      fixtures do
        @org = create(:organization)
        @another_org = create(:organization)

        @owner = create(:user, name: "#{@org}-owner").tap do |u|
          @org.add_admin(u)
          @another_org.add_admin(u)
        end
        @member = create(:user, name: "#{@org}-member").tap do |u|
          @org.add_member(u)
          @another_org.add_member(u)
        end

        @repo_v_team = create_repo("#{@org}-repo-v-team", owner: @org)
        @repo_s_team = create_repo("#{@org}-repo-s-team", owner: @org)
        @repo_admin = create_repo("#{@org}-repo-admin", owner: @org)
        @repo_write = create_repo("#{@org}-repo-write", owner: @org)
        @repo_read = create_repo("#{@org}-repo-read", owner: @org)
        @repo_admin_other = create_repo("#{@another_org}-repo-admin", owner: @another_org)
        @repo_write_other = create_repo("#{@another_org}-repo-write", owner: @another_org)
        @repo_read_other = create_repo("#{@another_org}-repo-read", owner: @another_org)

        @visible_team = create(:public_team, organization: @org, name: "#{@org}-visible-team").tap do |t|
          t.add_repository(@repo_v_team, :admin)
          t.add_repository(@repo_admin, :admin)
          t.add_repository(@repo_write, :write)
          t.add_repository(@repo_read, :read)
        end
        @secret_team = create(:secret_team, organization: @org, name: "#{@org}-secret-team").tap do |t|
          t.add_repository(@repo_s_team, :admin)
          t.add_repository(@repo_admin, :admin)
          t.add_repository(@repo_write, :write)
          t.add_repository(@repo_read, :read)
        end
        @visible_team_other = create(:public_team, organization: @another_org, name: "#{@another_org}-visible-team").tap do |t|
          t.add_repository(@repo_admin_other, :admin)
          t.add_repository(@repo_write_other, :write)
          t.add_repository(@repo_read_other, :read)
        end
        @secret_team_other = create(:secret_team, organization: @another_org, name: "#{@another_org}-secret-team").tap do |t|
          t.add_repository(@repo_admin_other, :admin)
          t.add_repository(@repo_write_other, :write)
          t.add_repository(@repo_read_other, :read)
        end
      end

      setup do
        @base_rel = Repository.where(organization_id: @org.id)
      end

      context "#apply" do
        test "filters to repos the team has :admin or :write for" do
          @owner.tap do |u|
            filter = ByTeam.new([], [], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@visible_team.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@visible_team_other.slug], [], organizations: [@org], user: u)
            assert_empty filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_s_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug, @secret_team_other.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_s_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new(["unknown"], [], organizations: [@org], user: u)
            assert_empty filter.apply(@base_rel)
          end

          @member.tap do |u|
            filter = ByTeam.new([], [], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@visible_team.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug], [], organizations: [@org], user: u)
            assert_empty filter.apply(@base_rel)

            filter = ByTeam.new(["unknown"], [], organizations: [@org], user: u)
            assert_empty filter.apply(@base_rel)

            filter = ByTeam.new([], [@secret_team.slug], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read]
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)
          end
        end

        test "is case insensitive" do
          expected_repos = [@repo_v_team, @repo_admin, @repo_write]

          [
            @visible_team.slug.downcase,
            @visible_team.slug.upcase,
          ].each do |incl_filter|
            filter = ByTeam.new([incl_filter], [], organizations: [@org], user: @owner)
            assert_same_elements expected_repos.map(&:name), filter.apply(@base_rel).map(&:name)
          end
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          assert ByTeam.new(nil, nil, organizations: [@org], user: @owner).is_empty?
          assert ByTeam.new([], [], organizations: [@org], user: @owner).is_empty?
          refute ByTeam.new([@visible_team.slug], [], organizations: [@org], user: @owner).is_empty?
          refute ByTeam.new([], [@visible_team.slug], organizations: [@org], user: @owner).is_empty?
          refute ByTeam.new([@secret_team.slug], [@visible_team.slug], organizations: [@org], user: @owner).is_empty?
        end
      end

      context "#has_incl_filters?" do
        test "returns proper result for has_incl_filters?" do
          refute ByTeam.new(nil, nil, organizations: [@org], user: @owner).has_incl_filters?
          refute ByTeam.new([], [], organizations: [@org], user: @owner).has_incl_filters?
          assert ByTeam.new([@visible_team.slug], [], organizations: [@org], user: @owner).has_incl_filters?
          refute ByTeam.new([], [@visible_team.slug], organizations: [@org], user: @owner).has_incl_filters?
          assert ByTeam.new([@secret_team.slug], [@visible_team.slug], organizations: [@org], user: @owner).has_incl_filters?
        end
      end

      def create_repo(name, owner:)
        create(:repository, name: name, owner: owner).tap do |r|
          create(:security_overview_analytics_repository, repository: r)
        end
      end
    end
  end
end
