# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamRolesTest < GitHub::TestCase
  fixtures do
    @org = create(:business_plus_org)
    @org_admin = create(:user, login: "org-admin")

    @org.add_admin(@org_admin)
    @org_member = create(:user, login: "org-member")
    @org.add_member(@org_member)

    @team = create(:team, organization: @org, creator: @org_member)
    @team.add_member(@org_admin)
    @team.add_member(@org_member)
  end

  context "maintainers" do
    test "are empty by default" do
      assert_empty @team.maintainers
    end
  end

  context "normal_members" do
    test "dont include maintainers" do
      assert_equal 1, @team.normal_members_sorted_by_login.count
      assert_includes @team.normal_members_sorted_by_login, @org_member
      @team.promote_maintainer(@org_member)
      assert_equal 0, @team.normal_members_sorted_by_login.count
    end

    test "dont include org owners" do
      assert_equal 1, @team.normal_members_sorted_by_login.count
      refute_includes @team.normal_members_sorted_by_login, @org_admin
    end
  end

  context "maintainers_and_owners_sorted_by_login" do
    test "dont include normal_members" do
      normal_member = create(:user, login: "normal-member")
      @org.add_member(normal_member)
      @team.add_member(normal_member)
      @team.promote_maintainer(@org_member)

      # only includes org owner (who is also team member) and team maintainer
      assert_equal 2, @team.maintainers_and_owners_sorted_by_login.count
      assert_includes @team.maintainers_and_owners_sorted_by_login, @org_admin
      assert_includes @team.maintainers_and_owners_sorted_by_login, @org_member
    end
  end

  context "promote_maintainer" do
    test "adds an admin" do
      refute_includes @team.maintainers, @org_member

      @team.promote_maintainer(@org_member)

      assert_includes @team.maintainers, @org_member
    end

    test "passes if the user is an org admin" do
      assert @team.promote_maintainer(@org_admin)
    end

    test "fails if the org member isn't already on the team" do
      non_team_member = create(:user, login: "non-team-member")
      @org.add_member(non_team_member)

      assert_raises Team::Roles::MemberRequiredError do
        @team.promote_maintainer(non_team_member)
      end

      refute @team.maintainer?(non_team_member)
    end

    test "instruments promoting org member to maintainer" do
      events = subscribe "team.promote_maintainer"
      expected_payload = {
        ldap_mapped: @team.ldap_mapped?,
        note: "Team #{@team}",
        team: @team.to_s,
        team_id: @team.id,
        org: @org.login,
        org_id: @org.id,
        user: @org_member.login,
        user_id: @org_member.id
      }

      @team.promote_maintainer(@org_member)

      assert event = events.pop, "an event was expected"
      assert_equal "team.promote_maintainer", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "demote_maintainer" do
    test "removes the admin" do
      @team.promote_maintainer(@org_member)
      @team.demote_maintainer(@org_member)

      assert_empty @team.maintainers
      assert @team.member?(@org_member)
    end

    test "grant team_writer role when demoting to a member that has posting ability" do
      @team.promote_maintainer(@org_member)
      @team.demote_maintainer(@org_member, with_posting_ability: true)

      assert_empty @team.maintainers
      assert Role.team_writer_role.user_ids.include?(@org_member.id)
      assert @team.member?(@org_member)
    end

    test "do not grant team_writer role when demoting to a member that does not have posting ability" do
      @team.promote_maintainer(@org_member)
      @team.demote_maintainer(@org_member, with_posting_ability: false)

      assert_empty @team.maintainers
      assert Role.team_writer_role.user_ids.empty?
      assert @team.member?(@org_member)
    end

    test "do not error if granting team_writer role to a member that already has team_writer role present" do
      @team.demote_maintainer(@org_member, with_posting_ability: true)
      assert Role.team_writer_role.user_ids.include?(@org_member.id)

      # a second demote with the intention of adding team_writer role which already exists on user
      @team.demote_maintainer(@org_member, with_posting_ability: true)
      assert Role.team_writer_role.user_ids.include?(@org_member.id)
    end

    test "fails if the user isn't already on the team" do
      non_team_member = create(:user, login: "non-team-member")

      assert_raises Team::Roles::MemberRequiredError do
        @team.demote_maintainer(non_team_member)
      end

      refute @team.maintainer?(non_team_member)
      refute @team.member?(non_team_member)
    end

    test "instruments demoting org member to maintainer" do
      events = subscribe "team.demote_maintainer"
      expected_payload = {
        ldap_mapped: @team.ldap_mapped?,
        note: "Team #{@team}",
        team: @team.to_s,
        team_id: @team.id,
        org: @org.login,
        org_id: @org.id,
        user: @org_member.login,
        user_id: @org_member.id
      }

      @team.demote_maintainer(@org_member)

      assert event = events.pop, "an event was expected"
      assert_equal "team.demote_maintainer", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "maintainer?" do
    test "is true when the user is a maintainer" do
      @team.promote_maintainer(@org_member)
      assert @team.maintainer?(@org_member)
    end

    test "is false when the user isn't a maintainer" do
      refute @team.maintainer?(@org_member)
    end
  end

  context "owner?" do
    test "is true when the user is an org admin" do
      team = create(:team, organization: @org, creator: @org_member)
      refute team.owner?(@org_admin)
      team.add_member(@org_admin)
      assert @team.owner?(@org_admin)
    end
  end
end
