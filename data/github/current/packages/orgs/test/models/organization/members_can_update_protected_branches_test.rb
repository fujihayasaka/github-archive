# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationMembersCanUpdateProtectedBranchesTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization, login: "the-org")
    @admin   = @org.admin
    @team    = create(:team, organization: @org, name: "the-team")
    @member = create(:user, login: "member")
    @member.emails.each(&:verify!)
    @team.add_member(@member)
  end

  test "is false by default" do
    assert_predicate @org, :members_can_update_protected_branches?
  end

  test "can be enabled for the org" do
    @org.disallow_members_can_update_protected_branches(actor: @admin)
    refute_predicate @org, :members_can_update_protected_branches?
  end

  test "can be disabled again for the org" do
    @org.disallow_members_can_update_protected_branches(actor: @admin)
    @org.allow_members_can_update_protected_branches(actor: @admin)
    assert_predicate @org, :members_can_update_protected_branches?
  end

  test "can be cleared for the org" do
    @org.disallow_members_can_update_protected_branches(actor: @admin)
    @org.clear_members_can_update_protected_branches(actor: @admin)
    assert_predicate @org, :members_can_update_protected_branches?
  end

  context "instrumentation" do
    test "instruments setting enable" do
      events = subscribe "org.members_can_update_protected_branches.disable"
      @org.disallow_members_can_update_protected_branches(actor: @admin)

      assert event = events.pop, "An event was expected"
    end

    test "instruments setting disable" do
      @org.disallow_members_can_update_protected_branches(actor: @admin)
      events = subscribe "org.members_can_update_protected_branches.enable"
      @org.allow_members_can_update_protected_branches(actor: @admin)

      assert event = events.pop, "An event was expected"
    end

    test "instruments setting clear" do
      @org.disallow_members_can_update_protected_branches(actor: @admin)
      events = subscribe "org.members_can_update_protected_branches.clear"
      @org.clear_members_can_update_protected_branches(actor: @admin)

      assert event = events.pop, "An event was expected"
    end
  end
end
