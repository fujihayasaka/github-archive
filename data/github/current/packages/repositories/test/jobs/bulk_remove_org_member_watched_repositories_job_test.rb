# typed: true
# frozen_string_literal: true

require "test_helper"

class BulkRemoveOrgMemberWatchedRepositoriesJobTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admin)
    @user = create(:user)
    @private_repo = create(:private_repository, :minimal, owner: @org)
    @private_repo2 = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
  end

  def perform_job
    perform_enqueued_jobs(only: [Newsies::DeleteAllForUserAndListsJob]) do
      BulkRemoveOrgMemberWatchedRepositoriesJob.perform_now(organization_ids: [@org.id], user_id: @user.id)
    end
  end

  test "#perform should remove watched repositories" do
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
    perform_job
    refute @user.watching_repo?(@private_repo), "expected user to not be watching repo"
  end

  test "#perform should not remove public watched repositories" do
    @org.add_member(@user)
    @user.watch_repo(@public_repo)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(@public_repo), "expected user to be watching repo"
    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
    perform_job
    refute @user.watching_repo?(@private_repo), "expected user to not be watching repo"
    assert @user.watching_repo?(@public_repo), "expected user to be watching repo"
  end

  test "#perform does not remove watched repository if repository is pullable by user" do
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)
    @private_repo.add_member(@user)

    perform_job
    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
  end

  test "#perform should remove watched repository if the repository is internal and no longer accessible to the user" do
    business = create(:business)
    business.add_organization(@org)
    @org.reload
    internal_repo = create(:internal_repository, owner: @org)

    @org.add_member(@user)
    @user.watch_repo(internal_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(internal_repo), "expected user to be watching repo"
    perform_job
    refute @user.watching_repo?(internal_repo), "expected user to not be watching repo"
  end

  test "#perform should not remove watched repository if the repository is internal and still accessible to the user" do
    business = create(:business)
    business.add_organization(@org)
    @org.reload
    internal_repo = create(:internal_repository, owner: @org)

    @org.add_member(@user)
    @user.watch_repo(internal_repo)

    org2 = create(:organization, business: business)
    org2.add_member(@user)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(internal_repo), "expected user to be watching repo"
    perform_job
    assert @user.watching_repo?(internal_repo), "expected user to still be watching repo"
  end
end
