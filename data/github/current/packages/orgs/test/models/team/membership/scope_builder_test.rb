# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamMembershipScopeBuilderTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "org-owner")
    @org = create(:organization, login: "some-organization", admin: @owner)
    @team = create(:team, organization: @org, name: "some-team", privacy: :closed)
    @member1 = create(:user, login: "team-member1")
    @team.add_member(@member1)

    @maintainer = create(:user, login: "team-maintainer")
    @team.add_member(@maintainer)
    @team.promote_maintainer(@maintainer)

    @member2 = create(:user, login: "other-member2")
    @team.add_member(@member2)

    @member3 = create(:user, login: "team-member3")
    @team.add_member(@member3)

    @member4 = create(:user, login: "other-member4")
    @team.add_member(@member4)

    @member5 = create(:user, login: "team-member5")
    @team.add_member(@member5)
  end

  context "loading all members" do
    test "returns all members of a team" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner).scope
      assert_same_elements [@member1.id, @maintainer.id, @member2.id, @member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "returns an empty scope when a team has no members" do
      empty_team = create(:team, name: "empty-team")
      assert_equal 0, empty_team.members.count

      scope = Team::Membership::ScopeBuilder.new(team_id: empty_team.id, viewer: @owner).scope
      assert_predicate scope.pluck(:id), :empty?
    end

  end

  context "paginating results" do
    test "returns the correct subset with after" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { after: @member2.id }).scope
      assert_same_elements [@member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "returns the correct subset with before" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { before: @member2.id }).scope
      assert_same_elements [@member1.id, @maintainer.id], scope.pluck(:id)
    end

    test "returns the correct subset with first" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { first: 2 }).scope
      # First 2 returns a set with 3 element as pagination logic uses this to determine
      # if there are results
      assert_same_elements [@member1.id, @maintainer.id, @member2.id], scope.pluck(:id)
    end

    test "returns the correct subset with last" do
      # Last 2 returns a set with 3 element as pagination logic uses this to determine
      # if there are results
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { last: 2 }).scope
      assert_same_elements [@member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "returns the correct subset with after & first" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { after: @member2.id, first: 2 }).scope
      # First 2 returns a set with 3 element as pagination logic uses this to determine
      # if there are results
      assert_same_elements [@member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "returns the correct subset with before & last" do
      # Last 2 returns a set with 3 element as pagination logic uses this to determine
      # if there are results
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, pagination: { before: @member4.id, last: 2 }).scope
      assert_same_elements [@maintainer.id, @member2.id, @member3.id], scope.pluck(:id)
    end

    test "does not return duplicates" do
      first_page = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :member, pagination: { first: 2 }).scope
      ids = first_page.pluck(:id)
      assert_same_elements [@member1.id, @member2.id, @member3.id], ids

      second_page = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :member, pagination: { first: 2, after: ids[1] }).scope
      ids = second_page.pluck(:id)
      assert_same_elements [@member3.id, @member4.id, @member5.id], ids

      third_page = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :member, pagination: { first: 2, after: ids[1] }).scope
      ids = third_page.pluck(:id)
      assert_same_elements [@member5.id], ids
    end
  end

  if GitHub.enterprise?
    context "loading all members for site admins" do
      test "returns all members of a team" do
        site_admin = create :staff_admin_user

        scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: site_admin).scope
        assert_same_elements [@member1.id, @maintainer.id, @member2.id, @member3.id, @member4.id, @member5.id], scope.pluck(:id)
      end
    end
  end

  context "filtering by 'role'" do
    test "returns only members when filtering for members" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :member).scope
      assert_same_elements [@member1.id, @member2.id, @member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "returns only maintainers when filtering for maintainers" do
      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :maintainer).scope
      assert_same_elements [@maintainer.id], scope.pluck(:id)
    end

    context "with the @owner as a team member" do
      test "excludes organization admins when filtering by 'member' role" do
        @team.add_member(@owner)
        scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :member).scope
        assert_same_elements [@member1.id, @member2.id, @member3.id, @member4.id, @member5.id], scope.pluck(:id)
      end

      test "includes organization admins when filtering by 'maintainer'" do
        @team.add_member(@owner)
        scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, role: :maintainer).scope
        assert_same_elements [@maintainer.id, @owner.id], scope.pluck(:id)
      end
    end
  end

  context "filtering by 'membership' type" do
    test "'child_team' membership returns only members of child teams" do
      child_team_member = create(:user, login: "child-team-member")
      child_team = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)
      child_team.add_member(child_team_member)

      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, membership: :child_team).scope
      assert_same_elements [child_team_member.id], scope.pluck(:id)
    end

    test "'child_team' membership doesn't return duplicate users" do
      child_team_member = create(:user, login: "child-team-member")
      child_team = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)
      child_team_2 = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)

      child_team.add_member(child_team_member)
      child_team_2.add_member(child_team_member)

      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, membership: :child_team).scope
      assert_same_elements [child_team_member.id], scope.pluck(:id)
    end

    test "'immediate' membership returns only members of the immediate team" do
      child_team_member = create(:user, login: "child-team-member")
      child_team = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)
      child_team.add_member(child_team_member)

      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner, membership: :immediate).scope
      assert_same_elements [@member1.id, @maintainer.id, @member2.id, @member3.id, @member4.id, @member5.id], scope.pluck(:id)
    end

    test "no membership filter returns both immediate and child team members" do
      child_team_member = create(:user, login: "child-team-member")
      child_team = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)
      child_team.add_member(child_team_member)

      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner).scope
      assert_same_elements [@member1.id, @maintainer.id, @member2.id, @member3.id, @member4.id, @member5.id, child_team_member.id], scope.pluck(:id)
    end

    test "no membership filter returns both immediate and child team members without duplicates" do
      child_team_member = create(:user, login: "child-team-member")
      child_team = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)
      child_team_2 = create(:team, organization: @team.organization, privacy: :closed, parent_team_id: @team.id)

      child_team.add_member(child_team_member)
      child_team_2.add_member(child_team_member)

      scope = Team::Membership::ScopeBuilder.new(team_id: @team.id, viewer: @owner).scope
      assert_same_elements [@member1.id, @maintainer.id, @member2.id, @member3.id, @member4.id, @member5.id, child_team_member.id], scope.pluck(:id)
    end
  end
end
