# typed: true
# frozen_string_literal: true

require "test_helper"

class RetiredNamespaceRaceConditionsTest < GitHub::IntegrationTestCase
  fixtures do
    @new_user_which_gets_renamed_to_original_user = create(:verified_user, login: "tatertotfood")
    @impostor_repo = create(:repository, name: "newertomato", owner: @new_user_which_gets_renamed_to_original_user)
  end

  # Related bug bounty issue: https://github.com/github/communities/issues/2102
  context "when a user and a repo are renamed at the same time" do
    test "user rename respects namespace lock" do
      create(:retired_namespace, owner: nil, owner_login: "expressnav", name: "tomato")

      Repository.any_instance.stubs(:ensure_name_not_retired).returns(true)

      Repositories::RepositoryOwnerLock.with_rename_lock(owner_id: @impostor_repo.owner_id) do
        @new_user_which_gets_renamed_to_original_user.rename!("expressnav")
      end

      # user does not get renamed
      assert_nil User.find_by(login: "expressnav")
      assert User.find_by(login: "tatertotfood")
    end

    test "repo rename respects namespace lock" do
      create(:retired_namespace, owner: nil, owner_login: "expressnav", name: "tomato")

      Repository.any_instance.stubs(:ensure_name_not_retired).returns(true)

      Repositories::RepositoryOwnerLock.with_rename_lock(owner_id: @new_user_which_gets_renamed_to_original_user.id) do
        @impostor_repo.rename("tomato")
      end

      # repo does not get renamed
      assert_nil Repository.find_by(owner_login: "tatertotfood", name: "tomato")
      assert Repository.find_by(owner_login: "tatertotfood", name: "newertomato")
    end

    test "User#rename! fails if a clashing namespace is detected " do
      create(:retired_namespace, owner: nil, owner_login: "expressnav", name: "tomato")

      @impostor_repo.rename("tomato")
      refute @new_user_which_gets_renamed_to_original_user.rename!("expressnav")
    end

    test "User#rename! fails if repository restoration is in progress" do
      repo = create(:repository, :soft_deleted, owner: @new_user_which_gets_renamed_to_original_user, name: "retired")
      refute repo.active?

      # ensure orchestration stops after the step before we release namespace lock
      RestoreRepositoryOrchestration.stubs(:stop_after_step).returns(:publish_restored)

      # start repo restoration
      orchestration = RepositoryOrchestration.restore(repo, actor: @new_user_which_gets_renamed_to_original_user)
      orchestration.execute(synchronous: true)

      # attempt user rename
      @new_user_which_gets_renamed_to_original_user.rename!("ownerA")
      @new_user_which_gets_renamed_to_original_user.reload

      # rename is not successful
      refute_equal @new_user_which_gets_renamed_to_original_user.login, "ownerA"

      Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: repo.owner_id)
    end

    test "Repository#rename fails if user login changes after lock is acquired" do
      # This mimics the scenario of a repository rename request being loaded
      # before the user rename request has completed. In that scenario, the
      # user's login will still have the old value so we call `owner#reload` in
      # the rename method to ensure that the login is what we expect once the
      # lock has been acquired.
      reloaded_user = stub(display_login: "cgbspender")
      @impostor_repo.owner.stubs(:reload).returns(reloaded_user)

      refute @impostor_repo.rename("tomato")
      assert Repository.find_by(owner_login: "tatertotfood", name: "newertomato")
    end
  end
end
