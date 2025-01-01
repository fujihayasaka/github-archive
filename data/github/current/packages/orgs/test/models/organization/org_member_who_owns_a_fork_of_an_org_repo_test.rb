# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationOrgMemberWhoOwnsAForkOfAnOrgRepoTest < GitHub::TestCase
  fixtures do
    @user  = create(:user)
    @owner = create(:user)
    @org   = create(:organization, admin: @owner)
    @repo  = create(:private_repository, owner: @org)
    @team  = create(:team, organization: @org, permission: "pull")

    @team.add_repository @repo, :pull
    @team.add_member @user

    @org.allow_private_repository_forking(actor: @owner)
    @forked_repo, @forked_reason = @repo.fork(forker: @user)
  end

  test "is always the admin" do
    assert @forked_repo.adminable_by?(@user)
  end
end
