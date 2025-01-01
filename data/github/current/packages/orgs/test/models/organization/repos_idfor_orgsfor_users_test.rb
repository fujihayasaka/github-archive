# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationReposIdforOrgsforUsersTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org2 = create(:organization)
    @team_org2 = create :team, organization: @org2, permission: "pull"

    @pub_repo = create(:repository, :minimal, owner: @org)
    @priv_repo = create(:private_repository, :minimal, owner: @org)
    @pub_repo2 = create(:repository, :minimal, owner: @org2)
    @priv_repo2 = create(:private_repository, :minimal, owner: @org2)
    @team_org2.add_repository(@priv_repo2, :pull)

    @user = create(:user)
    @org.add_admin(@user)
  end

  test "returns ids of all repos the user has access to" do
    @team_org2.add_member(@user)
    assert_same_elements [
      @pub_repo.id,
      @priv_repo.id,
      @pub_repo2.id,
      @priv_repo2.id,
    ], Organization.all_repo_ids_for_orgs_for_user([@org.id, @org2.id], @user)
  end

  test "returns ids of all repos the user has access to but exclude those who they don't" do
    @team_org2.remove_member(@user)
    assert_same_elements [
      @pub_repo.id,
      @priv_repo.id,
      @pub_repo2.id,
    ], Organization.all_repo_ids_for_orgs_for_user([@org.id, @org2.id], @user)
  end
end
