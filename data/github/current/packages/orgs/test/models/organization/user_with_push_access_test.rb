# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserWithPushAccessTest < GitHub::TestCase
  fixtures do
    @org  = create(:organization)
    @team = create(:team, organization: @org, permission: "push")
    @user = create(:user)
    @repo = create(:private_repository, :minimal, owner: @org)
    @repo.update_attribute(:owner, @org)

    @team.add_member @user
    @team.add_repository @repo, :push

    @team2 = create(:team, organization: @org, permission: "push")
    @team2.add_member @user

    @assigned_issue = create :issue, repository: @repo, user: @user, assignee: @user
  end

  test "knows if he can view a repo" do
    assert @repo.pullable_by?(@user)
  end

  test "knows if he can push to a repo" do
    assert @repo.pushable_by?(@user)
  end

  test "knows if he can admin a repo" do
    assert !@repo.adminable_by?(@user)
  end
end
