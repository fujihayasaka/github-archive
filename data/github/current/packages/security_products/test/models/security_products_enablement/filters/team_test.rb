# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProductsEnablement
  module Filters
    class TeamTest < GitHub::TestCase
      setup do
        business = create(:global_business)
        @org = create(:organization, business: business)
        @another_org = create(:organization, business: business)

        @owner = create(:user, name: "#{@org}-owner").tap do |u|
          @org.add_admin(u)
          @another_org.add_admin(u)
        end
        @member = create(:user, name: "member").tap do |u|
          @another_org.add_admin(u)
        end

        @security_manager = create(:user)
        @org.add_member(@security_manager)
        security_team = create(:security_manager_team, organization: @org)
        security_team.add_member(@security_manager)

        @repo_v_team = create(:repository, owner: @org, name: "repo-v-team")
        @repo_s_team = create(:repository, owner: @org, name: "repo-s-team")
        @repo_admin = create(:repository, owner: @org, name: "repo-admin")
        @repo_write = create(:repository, owner: @org, name: "repo-write")
        @repo_read = create(:repository, owner: @org, name: "repo-read")

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
      end

      context "#apply" do
        test "returns an empty array when no filter is supported by the class" do
          filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "configuration" => ["config-name"] })
          assert_empty filter.apply
        end

        context "team filter" do
          test "return an empty array when team does not exist" do
            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "team" => ["test"] })
            assert_empty filter.apply
          end

          test "returns an empty array when user is not a member of the organization" do
            filter = SecurityProductsEnablement::Filters::Team.new(@member, @org, { "team" => [@visible_team.name] })
            assert_empty filter.apply
          end

          test "returns repo IDs the team has :admin or :write access for" do
            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "team" => [@visible_team.name] })
            assert_same_elements [@repo_v_team.id, @repo_admin.id, @repo_write.id], filter.apply

            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "team" => [@secret_team.name] })
            assert_same_elements [@repo_s_team.id, @repo_admin.id, @repo_write.id], filter.apply

            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "team" => [@visible_team.name, @secret_team.name] })
            assert_same_elements [@repo_v_team.id, @repo_s_team.id, @repo_admin.id, @repo_write.id], filter.apply

            # Security manager cannot see the secret repo unless added to the team
            filter = SecurityProductsEnablement::Filters::Team.new(@security_manager, @org, { "team" => [@visible_team.name, @secret_team.name] })
            assert_same_elements [@repo_v_team.id, @repo_admin.id, @repo_write.id], filter.apply

            @secret_team.add_member(@security_manager)
            filter = SecurityProductsEnablement::Filters::Team.new(@security_manager, @org, { "team" => [@visible_team.name, @secret_team.name] })
            assert_same_elements [@repo_v_team.id, @repo_s_team.id, @repo_admin.id, @repo_write.id], filter.apply
          end
        end

        context "negated team filter" do
          test "returns an empty array when user is not a member of the organization" do
            filter = SecurityProductsEnablement::Filters::Team.new(@member, @org, { "-team" => [@visible_team.name] })
            assert_empty filter.apply
          end

          test "returns repo IDs the team has :admin or :write access for" do
            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "-team" => [@visible_team.name] })
            assert_same_elements [@repo_s_team.id, @repo_admin.id, @repo_write.id], filter.apply

            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "-team" => [@secret_team.name] })
            assert_same_elements [@repo_v_team.id, @repo_admin.id, @repo_write.id], filter.apply

            filter = SecurityProductsEnablement::Filters::Team.new(@owner, @org, { "-team" => [@visible_team.name, @secret_team.name] })
            assert_empty filter.apply

            filter = SecurityProductsEnablement::Filters::Team.new(@security_manager, @org, { "-team" => [@visible_team.name] })
            assert_empty filter.apply

            @secret_team.add_member(@security_manager)
            filter = SecurityProductsEnablement::Filters::Team.new(@security_manager, @org, { "-team" => [@visible_team.name] })
            assert_same_elements [@repo_s_team.id, @repo_admin.id, @repo_write.id], filter.apply
          end
        end
      end
    end
  end
end
