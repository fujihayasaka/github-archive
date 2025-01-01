# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityCenter
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

      context "#apply" do
        test "returns rel.none if no orgs are provided and filter is specified" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByTeam.new([@visible_team.slug], [], organizations: [], user: @owner)
          assert_empty filter.apply(rel)

          filter = ByTeam.new([], [@visible_team.slug], organizations: [], user: @owner)
          assert_empty filter.apply(rel)
        end

        test "returns all results if no orgs are provided and filter is not specified" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          filter = ByTeam.new([], [], organizations: [], user: @owner)
          assert_equal rel.length, filter.apply(rel).length
        end

        test "filters to repos the team has :admin or :write for" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          @owner.tap do |u|
            filter = ByTeam.new([], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read, @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@visible_team.slug], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_v_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@visible_team_other.slug], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_admin_other, @repo_write_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@visible_team.slug, @visible_team_other.slug], [], organizations: [@another_org], user: u)
            expected_repos = [@repo_admin_other, @repo_write_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_s_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@secret_team_other.slug], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_admin_other, @repo_write_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug, @secret_team_other.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_s_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new(["unknown"], [], organizations: [@org], user: u)
            assert_empty filter.apply(rel)

            filter = ByTeam.new([], [@visible_team.slug, @visible_team_other.slug], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_s_team, @repo_read, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([], [@secret_team.slug], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_read, @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([], ["unknown"], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read, @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
          end

          @member.tap do |u|
            filter = ByTeam.new([], [], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read,  @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@visible_team.slug], [], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_admin, @repo_write]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([@secret_team.slug], [], organizations: [@org], user: u)
            assert_empty filter.apply(rel)

            filter = ByTeam.new(["unknown"], [], organizations: [@org], user: u)
            assert_empty filter.apply(rel)

            filter = ByTeam.new([], [@visible_team.slug, @visible_team_other.slug], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_s_team, @repo_read, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([], [@secret_team.slug], organizations: [@org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read, @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

            filter = ByTeam.new([], ["unknown"], organizations: [@org, @another_org], user: u)
            expected_repos = [@repo_v_team, @repo_s_team, @repo_admin, @repo_write, @repo_read, @repo_admin_other, @repo_write_other, @repo_read_other]
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
          end
        end

        test "is case insensitive" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)
          expected_repos = [@repo_v_team, @repo_admin, @repo_write]

          [
            @visible_team.slug.downcase,
            @visible_team.slug.upcase,
            @visible_team.combined_slug.downcase,
            @visible_team.combined_slug.upcase,
          ].each do |incl_filter|
            filter = ByTeam.new([incl_filter], [], organizations: [@org], user: @owner)
            assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
          end
        end

        test "filters by team slug across orgs" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          org1 = create(:organization, admin: @owner)
          org2 = create(:organization, admin: @owner)

          repo1 = create_repo("repo-1", owner: org1)
          repo2 = create_repo("repo-2", owner: org2)

          team1 = create(:public_team, organization: org1, name: "my-team").tap do |t|
            t.add_repository(repo1, :admin)
          end
          team2 = create(:public_team, organization: org2, name: "my-team").tap do |t|
            t.add_repository(repo2, :admin)
          end

          filter = ByTeam.new(["my-team"], [], organizations: [org1, org2], user: @owner)
          expected_repos = [repo1, repo2]
          assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
        end

        test "filters by combined slug within specified org" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          org1 = create(:organization, admin: @owner)
          org2 = create(:organization, admin: @owner)

          repo1 = create_repo("repo-1", owner: org1)
          repo2 = create_repo("repo-2", owner: org2)

          team1 = create(:public_team, organization: org1, name: "my-team").tap do |t|
            t.add_repository(repo1, :admin)
          end
          team2 = create(:public_team, organization: org2, name: "my-team").tap do |t|
            t.add_repository(repo2, :admin)
          end

          filter = ByTeam.new(["#{org1}/my-team"], [], organizations: [org1, org2], user: @owner)
          expected_repos = [repo1]
          assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)

          filter = ByTeam.new(["#{org2}/my-team"], [], organizations: [org1, org2], user: @owner)
          expected_repos = [repo2]
          assert_same_elements expected_repos.map(&:name), filter.apply(rel).map(&:name)
        end

        test "returns no results for unknown org in a combined slug filter" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          org1 = create(:organization, admin: @owner)
          org2 = create(:organization, admin: @owner)

          repo1 = create_repo("repo-1", owner: org1)
          repo2 = create_repo("repo-2", owner: org2)

          team1 = create(:public_team, organization: org1, name: "my-team").tap do |t|
            t.add_repository(repo1, :admin)
          end
          team2 = create(:public_team, organization: org2, name: "my-team").tap do |t|
            t.add_repository(repo2, :admin)
          end

          filter = ByTeam.new(["unknown-org/my-team"], [], organizations: [org1, org2], user: @owner)
          assert_empty filter.apply(rel).map(&:name)
        end

        test "returns no results for unknown team in a combined slug filter" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          org1 = create(:organization, admin: @owner)
          org2 = create(:organization, admin: @owner)

          repo1 = create_repo("repo-1", owner: org1)
          repo2 = create_repo("repo-2", owner: org2)

          team1 = create(:public_team, organization: org1, name: "my-team").tap do |t|
            t.add_repository(repo1, :admin)
          end
          team2 = create(:public_team, organization: org2, name: "my-team").tap do |t|
            t.add_repository(repo2, :admin)
          end

          filter = ByTeam.new(["#{org1}/unknown-team"], [], organizations: [org1, org2], user: @owner)
          assert_empty filter.apply(rel).map(&:name)
        end

        test "returns no results for invalid combined slug filter" do
          rel = RepositorySecurityCenterConfig.all.left_outer_joins(:repository_security_center_statuses).group(:repository_id)

          org1 = create(:organization, admin: @owner)
          org2 = create(:organization, admin: @owner)

          repo1 = create_repo("repo-1", owner: org1)
          repo2 = create_repo("repo-2", owner: org2)

          team1 = create(:public_team, organization: org1, name: "my-team").tap do |t|
            t.add_repository(repo1, :admin)
          end
          team2 = create(:public_team, organization: org2, name: "my-team").tap do |t|
            t.add_repository(repo2, :admin)
          end

          filter = ByTeam.new(["/my-team"], [], organizations: [org1, org2], user: @owner)
          assert_empty filter.apply(rel).map(&:name)

          filter = ByTeam.new(["#{org1}/"], [], organizations: [org1, org2], user: @owner)
          assert_empty filter.apply(rel).map(&:name)

          filter = ByTeam.new(["#{org1}/my-team/extra"], [], organizations: [org1, org2], user: @owner)
          assert_empty filter.apply(rel).map(&:name)
        end
      end

      context "#is_empty?" do
        test "returns proper result for is_empty?" do
          assert ByTeam.new(nil, nil, organizations: [@org], user: @owner).is_empty?
          assert ByTeam.new([], [], organizations: [@org], user: @owner).is_empty?
          refute ByTeam.new([@visible_team.slug], [], organizations: [@org], user: @owner).is_empty?
          refute ByTeam.new([], [@visible_team.slug], organizations: [@org], user: @owner).is_empty?
        end
      end

      def create_repo(name, owner:, visibility: :private, archived: false, enabled_features: [], not_enabled_features: [], create_not_enabled_statuses_for_unspecified_features: true)
        factory = if visibility == :private
          :private_repository
        elsif visibility == :public
          :repository
        elsif visibility == :internal
          :internal_repository
        end

        create(factory, name: name, owner: owner).tap do |r|
          r.set_archived if archived

          create(
            :repository_security_center_config,
            repository: r,
            ghas_enabled: true,
          )

          all_feature_types = RepositorySecurityCenterStatus.primary_feature_types.flat_map do |primary_type|
            [primary_type] + RepositorySecurityCenterStatus.subfeatures_for(primary_type)
          end

          enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: true)
          end

          not_enabled_features.each do |feature|
            raise "Unknown feature type #{feature}" unless all_feature_types.include?(feature)
            create_status(r, feature: feature, enrolled: false)
          end

          if create_not_enabled_statuses_for_unspecified_features
            (all_feature_types - enabled_features - not_enabled_features).each do |feature|
              create_status(r, feature: feature, enrolled: false)
            end
          end
        end
      end

      def create_status(repo, feature:, enrolled:)
        create(
          :repository_security_center_status,
          feature,
          enrolled ? :enrolled : :not_enrolled,
          repository: repo,
        )
      end
    end
  end
end
