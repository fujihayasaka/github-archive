# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserWithAdminAccessTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @org2 = create(:organization)
    @team = create(:team, organization: @org, permission: "admin")
    @user = create(:user)
    @repo = create(:private_repository, :minimal, owner: @org)
    @repo.update_attribute(:owner, @org)

    @team.add_member @user
    @team.add_repository @repo, :admin
  end

  test "knows if he can view a repo" do
    assert @repo.pullable_by?(@user)
  end

  test "knows if he can push to a repo" do
    assert @repo.pushable_by?(@user)
  end

  test "knows if he can admin a repo" do
    assert @repo.adminable_by?(@user)
  end

  test "knows he can't admin an organization" do
    refute @org.adminable_by?(@user)
  end

  test "knows which organizations he is a member of" do
    assert_equal [@org], @user.organizations
  end

  test "can ask if she's a member of an organization" do
    assert @org.direct_or_team_member?(@user)
    refute @org2.direct_or_team_member?(@user)
  end
end
