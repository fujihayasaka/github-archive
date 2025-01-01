# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationForkingARepoOnBehalfOfAnOrganizationTest < GitHub::TestCase
  fixtures do
    @dude = create :user, plan: "medium"

    @repo  = create(:repository, owner: @dude)
    @repo2 = create(:repository, :minimal, owner: @dude)
    @repo3 = create(:private_repository, :minimal, owner: @dude)

    @owner  = create :user, plan: "medium"
    @owner2 = create(:user)
    @org    = create(:organization, admin: @owner)
    @org.add_admin(@owner2)

    @org.disallow_members_can_create_repositories(actor: @owner)

    other_org = create(:organization)
    other_org.add_admin(@owner)
    other_org.allow_private_repository_forking(actor: @owner)

    @org_private_repo = create(:private_repository, owner: other_org)

    @team  = create(:team, organization: @org, permission: "admin")
    @team2 = create(:team, organization: @org, permission: "push")

    @user  = create(:user)
    @user2 = create(:user)
    @user3 = create(:user)

    @repo3.add_member @owner

    @team.add_member @user
    @team2.add_member @user2

    @owner_repo = create(:private_repository, owner: @owner)
  end

  test "works for an Owner" do
    forked = create(:fork_repository, forker: @owner, organization: @org, fork_repo: @repo)
    assert forked
    assert_equal_owner @org, forked.owner
  end

  test "only adds it to the first team if there is more than one admin team" do
    team3  = create(:team, organization: @org, permission: "admin")
    team3.add_member @user

    forked, reason = @repo.fork(org: @org, forker: @user)
    assert forked
    assert_includes @org.repositories, forked
    assert !team3.repositories.include?(forked)
  end

  test "fails if the user isn't an admin of any teams" do
    forked, reason = @repo.fork(org: @org, forker: @user2)
    refute forked
  end

  test "fails if the user isn't in the org" do
    forked, reason = @repo.fork(org: @org, forker: @user3)
    assert !forked
  end

  if GitHub.billing_enabled?
    test "billing email required" do
      org = Organization.new billing_email: nil, login: "githubc2", admin: @user
      assert !org.valid?, "org is valid"
      assert org.errors[:billing_email].any?
    end
  else
    test "billing email is not required" do
      org = Organization.new billing_email: nil, login: "githubc2", admin: @user
      assert org.valid?, "org isn't valid"
      assert org.errors[:billing_email].blank?
    end
  end

  test "gravatar email defaults to nil" do
    assert_nil @org.gravatar_email
  end

  test "gravatar email can be set to something" do
    gmail = "cwanstrath+gravatar@gmail.com"
    @org.update! gravatar_email: gmail
    assert_equal gmail, @org.gravatar_email
  end

  test "gravatar email can be set to an existing email" do
    @org.update! gravatar_email: @user.email
    assert_equal @user.email, @org.gravatar_email
  end

  test "gravatar emails aren't unique" do
    @org.update! gravatar_email: @user.email
    assert_equal @user.email, @org.gravatar_email

    org2 = create :organization, admin: create(:user)
    org2.update! gravatar_email: @user.email
    assert_equal @user.email, org2.gravatar_email
  end

  test "gravatar email changes update cached gravatar_id" do
    @org.update! gravatar_email: @user.email
    assert_equal GitHub.generate_gravatar_id(@user.email), @org.reload.gravatar_id

    @org.update! gravatar_email: "bear@ski-trail.org"
    assert_equal "8651394cae1d100b3f57f546caba8c1e", @org.reload.gravatar_id
  end

  test "works if the target is private but the user has access" do
    forked, reason = @org_private_repo.fork(org: @org, forker: @owner2)
    assert !forked

    forked, reason = @org_private_repo.fork(org: @org, forker: @owner)
    assert forked
  end

  test "works if the target is private but the user owns it" do
    forked, reason = @owner_repo.fork(org: @org, forker: @owner)
    assert forked
  end
end
