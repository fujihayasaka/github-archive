# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOwnerTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org  = create(:organization, admin: @user)
    @repo = create(:private_repository, :minimal, owner: @org)
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

  test "knows he can admin an organization" do
    assert @org.adminable_by?(@user)
  end

  test "knows which organizations he is a member of" do
    assert_equal [@org], @user.organizations
  end

  test "can ask if she's a member of an organization" do
    assert @org.direct_or_team_member?(@user)
    refute Organization.new.direct_or_team_member?(@user)
  end
end
