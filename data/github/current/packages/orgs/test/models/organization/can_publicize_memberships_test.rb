# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCanPublicizeMembershipsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @actor = create(:user)
  end

  setup do
    disable_feature_flag(:discard_stratocaster_fanout)
  end

  test "returns true for an org member trying to publicize themselves" do
    member = create(:user)
    @org.add_member member

    assert @org.can_publicize_memberships?(member, members: [member])
  end

  test "returns false for an org member trying to publicize a different org member" do
    member = create(:user)
    other = create(:user)
    @org.add_member member
    @org.add_member other

    refute @org.can_publicize_memberships?(member, members: [other])
  end

  test "returns false for org owner trying to publicize a different org member" do
    admin = create(:user)
    @org.add_admin admin

    member = create(:user)
    @org.add_member member

    refute @org.can_publicize_memberships?(admin, members: [member])
  end

  test "returns false if the requesting user is an org" do
    member = create(:user)
    @org.add_member member

    refute @org.can_publicize_memberships?(@org, members: [member])
  end

  if GitHub.enterprise?
    test "returns false if default private visibility enforced" do
      GitHub.set_default_org_membership_visibility("private", @actor, true)

      member = create :user
      @org.add_member member

      refute @org.can_publicize_memberships?(member, members: [member])
    end
  end
end
