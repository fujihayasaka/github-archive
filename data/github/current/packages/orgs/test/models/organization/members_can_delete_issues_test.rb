# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationMembersCanDeleteIssuesTest < GitHub::TestCase
  fixtures do
    @org     = create(:organization, login: "the-org")
    @admin   = @org.admin
    @team    = create(:team, organization: @org, name: "the-team")
    @member = create(:user, login: "member")
    @member.emails.each(&:verify!)
    @team.add_member(@member)
  end

  test "is false by default" do
    refute_predicate @org, :members_can_delete_issues?
  end

  test "can be enabled for the org" do
    @org.allow_members_can_delete_issues(actor: @admin)
    assert_predicate @org, :members_can_delete_issues?
  end

  test "can be disabled again for the org" do
    @org.allow_members_can_delete_issues(actor: @admin)
    @org.disallow_members_can_delete_issues(actor: @admin)
    refute_predicate @org, :members_can_delete_issues?
  end
end
