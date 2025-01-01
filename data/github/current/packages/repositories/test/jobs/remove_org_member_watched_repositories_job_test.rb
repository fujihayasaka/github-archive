# typed: false
# frozen_string_literal: true

require "test_helper"
require File.join(Rails.root, "packages/repositories/test/jobs/legacy_remove_org_member_data_common_tests")

class RemoveOrgMemberWatchedRepositoriesJobTest < GitHub::TestCase
  include LegacyRemoveOrgMemberDataCommonTests

  fixtures do
    @restorable_org_user = create :restorable_organization_user
    @org = @restorable_org_user.organization
    @org.allow_private_repository_forking(actor: @org.admin)
    @user = @restorable_org_user.user
    @restorable = @restorable_org_user.restorable
    @private_repo = create(:private_repository, :minimal, owner: @org)
    @private_repo2 = create(:private_repository, :minimal, owner: @org)
    @public_repo = create(:repository, :minimal, owner: @org)
    @job_args = { "organization_id" => @org.id, "user_id" => @user.id }
  end

  def perform_job(*args)
    perform_enqueued_jobs(only: [Newsies::DeleteAllForUserAndListsJob]) do
      RemoveOrgMemberWatchedRepositoriesJob.perform_now(*args)
    end
  end

  test "enqueues job for removing an organization user" do
    assert_enqueued_with job: RemoveOrgMemberWatchedRepositoriesJob, queue: "remove_org_member_watched_repositories" do
      RemoveOrgMemberWatchedRepositoriesJob.enqueue(@org, @user)
    end
  end

  test "#perform should remove watched repositories" do
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
    perform_job(@job_args)
    refute @user.watching_repo?(@private_repo), "expected user to not be watching repo"
  end

  test "#perform should not remove public watched repositories" do
    @org.add_member(@user)
    @user.watch_repo(@public_repo)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert @user.watching_repo?(@public_repo), "expected user to be watching repo"
    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
    perform_job(@job_args)
    refute @user.watching_repo?(@private_repo), "expected user to not be watching repo"
    assert @user.watching_repo?(@public_repo), "expected user to be watching repo"
  end

  test "#perform does not remove watched repository if repository is pullable by user" do
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)
    @private_repo.add_member(@user)

    perform_job(@job_args)
    assert @user.watching_repo?(@private_repo), "expected user to be watching repo"
  end

  test "#perform should add multiple watched repository restorables" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @user.watch_repo(@private_repo2)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::WatchedRepository.count", 2 do
      perform_job(@job_args)
    end
  end

  test "#perform should not create watched repository restorables for public repos" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @org.add_member(@user)
    @user.watch_repo(@public_repo)
    @user.watch_repo(@private_repo)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::WatchedRepository.count", 1 do
      perform_job(@job_args)
    end
  end

  test "#perform does not create restorables if no Restorable::OrganizationUser record is found" do
    user = create(:user)
    @org.add_member(user)
    user.watch_repo(@private_repo)
    user.watch_repo(@private_repo2)
    @org.remove_member_without_callbacks_and_notifications(user)

    assert_difference "Restorable::WatchedRepository.count", 0 do
      perform_job(@job_args)
    end
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
    perform_job(@job_args)
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
    perform_job(@job_args)
    assert @user.watching_repo?(internal_repo), "expected user to still be watching repo"
  end

  test "#perform should mark watched repository restorable as complete" do
    GitHub.flipper[:org_remove_member_cleanup_in_bulk_test_only].disable # This feature does not create restorables
    @org.add_member(@user)
    @user.watch_repo(@private_repo)
    @user.watch_repo(@private_repo2)
    @org.remove_member_without_callbacks_and_notifications(@user)

    assert_difference "Restorable::WatchedRepository.count", 2 do
      perform_job(@job_args)
    end

    assert @restorable.saved?(:restorable_watched_repositories),
      "expected restorable_watched_repositories to be saved"
  end
end
