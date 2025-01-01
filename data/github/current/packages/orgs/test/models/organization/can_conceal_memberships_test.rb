# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationCanConcealMembershipsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @actor = create(:user)
  end

  test "returns true for org owner concealing an org member" do
    admin = create(:user)
    @org.add_admin admin

    member = create(:user)
    @org.add_member member

    assert @org.can_conceal_memberships?(admin, members: [member])
  end

  test "returns true for an org member concealing themselves" do
    member = create(:user)
    @org.add_member member

    assert @org.can_conceal_memberships?(member, members: [member])
  end

  test "returns false if the requesting user is an org" do
    member = create(:user)
    @org.add_member member

    refute @org.can_conceal_memberships?(@org, members: [member])
  end

  if GitHub.enterprise?
    test "returns false if default public visibility enforced" do
      GitHub.set_default_org_membership_visibility("public", @actor, true)

      member = create :user
      @org.add_member member

      refute @org.can_conceal_memberships?(member, members: [member])
    end
  end
end
