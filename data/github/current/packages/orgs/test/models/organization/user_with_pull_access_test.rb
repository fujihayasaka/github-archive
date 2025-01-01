# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserWithPullAccessTest < GitHub::TestCase
  fixtures do
    @org   = create(:organization)
    @team  = create(:team, organization: @org)
    @user  = create(:user)
    @user2 = create(:user)
    @repo  = create(:private_repository, :minimal, owner: @org)
    @repo.update_attribute(:owner, @org)

    @team.add_member @user
    @team.add_repository @repo, :pull
  end

  test "knows if he can view a repo" do
    assert @repo.pullable_by?(@user)
  end

  test "knows if he can push to a repo" do
    assert !@repo.pushable_by?(@user)
  end

  test "knows if he can admin a repo" do
    assert !@repo.adminable_by?(@user)
  end

  test "knows what teams he's on" do
    assert_equal [@team], @user.teams
  end

  test "non-team user can't view a repo" do
    assert !@repo.pullable_by?(@user2)
  end
end
