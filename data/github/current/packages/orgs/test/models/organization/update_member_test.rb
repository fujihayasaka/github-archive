# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUpdateMemberTest < GitHub::TestCase
  test "performs the update immediately for orgs with few dependents" do
    org = create(:organization)
    member = create(:user)
    org.add_member(member, action: :read)
    project = create(:project, name: "Dependent", owner: org)

    refute org.adminable_by?(member)
    refute project.adminable_by?(member)

    org.update_member(member, action: :admin)

    assert org.adminable_by?(member), "member should have been granted admin on the org"
    assert project.adminable_by?(member), "member should have admin on owner ability over the project"
  end

  test "cancels pending invitations from the member" do
    org = create(:organization)
    inviter = create(:user)
    org.add_member(inviter, action: :admin)
    invitee = create(:user)

    invitation = org.invite(invitee, inviter: inviter)
    assert_nil invitation.cancelled_at
    org.update_member(inviter, action: :read)
    invitation.reload
    refute_nil invitation.cancelled_at
  end

  test "does not cancel accepted invitations from the member" do
    org = create(:organization)
    inviter = create(:user)
    org.add_member(inviter, action: :admin)
    invitee = create(:user)

    invitation = org.invite(invitee, inviter: inviter)
    assert_equal OrganizationInvitation.count, 1
    invitation.accept
    org.update_member(inviter, action: :read)
    assert_equal OrganizationInvitation.count, 1
  end
end
