# typed: true
# frozen_string_literal: true

require "test_helper"

class UserAbilitiesTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, plan: GitHub::Plan.find!("medium"))
    @user = create(:user)
    @another_user = create(:user)
    @org = create(:organization)
    @private_repo = create(:private_repository, owner: @owner)

    @org.add_member @user
    @private_repo.add_member @user
  end

  test "can read repositories owned by orgs user can read" do
    repo = create(:repository, owner: @org)
    @org.add_member @user
    assert_able @user, :read, @org
    assert_able @user, :read, repo
  end

  test "user can admin themselves" do
    assert_able @user, :admin, @user
  end

  test "user cannot admin another user" do
    refute_able @user, :admin, @another_user
  end

  test "org cannot admin a member user" do
    @org.add_member @user
    refute_able @org, :admin, @user
  end

  test "org admin cannot admin a member user" do
    @org.add_admin @owner
    @org.add_admin @user
    refute_able @owner, :admin, @user
  end
end
