# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryUserIdsToHideFromMentionsTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    only = [RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @org.admins.first) }
    @repo = create(:private_repository, owner: @org)
    team = create(:team, organization: @org)
    team.add_repository(@repo, :pull)
    10.times { team.add_member(create(:user)) }
    @extra_user = create(:user)
    @org.add_member(@extra_user)
  end

  test "no users to hide in a public repository" do
    repo_public = create(:public_repository, owner: @org)
    user_ids_without_explicit_access = @org.members.map(&:id) - repo_public.all_user_ids
    refute user_ids_without_explicit_access.empty?
    assert repo_public.user_ids_to_hide_from_mentions(user_ids_without_explicit_access).empty?
  end

  test "will return the id's of all the users who do not have access to this repo" do
    user2 = create(:user)
    users_with_no_access = [@extra_user, user2]
    user_ids_to_hide = @repo.user_ids_to_hide_from_mentions(@org.members + users_with_no_access)
    assert_equal users_with_no_access.length, user_ids_to_hide.length
    users_with_no_access.each { |user| assert user_ids_to_hide.include?(user.id) }
  end

  test "will not return the user's id if it's an Mannequin" do
    user = create(:mannequin)
    users_with_no_access = [user]
    user_ids_to_hide = @repo.user_ids_to_hide_from_mentions(users_with_no_access)
    assert_equal user_ids_to_hide.length, 0
  end

  test "succeeds even when user_ids list has invalid ids" do
    user = create(:user)
    users_with_no_access = [user.id, -1]
    user_ids_to_hide = @repo.user_ids_to_hide_from_mentions(users_with_no_access)
    assert_equal user_ids_to_hide.length, 2
  end

  test "will return [] even if user doesn't have access, if the parent org is deemed too large" do
    PermissionCache.enable do
      assert @repo.user_ids_to_hide_from_mentions([@extra_user], optimize_repo_access_checks: true).include?(@extra_user.id)
    end

    PermissionCache.enable do
      @repo.expects(:large_membership_org_owner?).once.returns(true)
      assert @repo.user_ids_to_hide_from_mentions([@extra_user], optimize_repo_access_checks: true).empty?
    end
  end

  test "will run the access checks if optimize_repo_access_checks is false, without checking org size" do
    PermissionCache.enable do
      @repo.expects(:large_membership_org_owner?).never
      @repo.owner.expects(:members_count).never
      assert @repo.user_ids_to_hide_from_mentions([@extra_user], optimize_repo_access_checks: false).include?(@extra_user.id)
    end
  end

  test "will return the user's id if user doesn't have access, the parent org is too big, but the ids have already been cached" do
    PermissionCache.enable do
      @repo.expects(:large_membership_org_owner?).once.returns(true)
      assert @repo.user_ids_to_hide_from_mentions([@extra_user], optimize_repo_access_checks: false).include?(@extra_user.id)
      assert @repo.user_ids_to_hide_from_mentions([@extra_user], optimize_repo_access_checks: true).include?(@extra_user.id)
    end
  end
end
