# typed: false
# frozen_string_literal: true

require "test_helper"

class RepositoryRestoreDependencyTest < ::GitHub::TestCase
  include HydroTestHelpers
  include HydroMessageJobTestHelpers

  def inline_remove(repo, remover: repo.owner)
    perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) do
      repo.remove(remover, synchronous: true)
    end
  end

  fixtures do
    @user = create(:user)
    @actor = create(:user)
    @org = create(:enterprise_linked_organization)
    @org_repo = create(:private_repository, owner: @org, from_example: :simple)
    @user_repo = create(:private_repository, from_example: :simple)

    repo = create :repository, owner: @user
    repo.initialize_wiki(repo.owner)
    example_repo :wiki, repo.unsullied_wiki
    issue = create :issue, repository: repo, user: @user

    inline_remove(repo)

    @archived = Repositories::Public.find_deleted(repo.id)
  end

  setup do
    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:repo_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/simple.git")
    Repository::StorageAdapter::RemoteShardedStorageAdapter.any_instance.stubs(:wiki_backup_location).returns("#{Rails.root}/test/fixtures/git/examples/wiki.git")

    # We don't actually have the repo in backup, so we copy it from the sample
    # repository. We take over the client-side because it's harder to figure out
    # which path is the current one if we take over the client-side.
    GitRPC::Client.any_instance.stubs(:gitbackups_restore).with do |spec|
      GitHub::GitbackupsTestHelper.restore_from_example(spec)
    end
  end

  # clear the restored repository from disk so that it is ready to be restored again
  teardown do
    next if GitHub.enterprise? # enterprise needs the disk data, we don't delete it in prod either!

    repository = Repositories::Public.get_active_or_deleted(@archived.id)
    next unless repository

    repository.remove_from_disk
    repository.remove_wiki_from_disk
  end

  test "restores repository" do
    Repository.restore(@archived.id, actor: @actor)

    repo = Repositories::Public.find_active!(@archived.id)
    assert repo.present?
  end

  test "restores repository from soft deletion" do
    repo = create :repository, owner: @user

    inline_remove(repo, remover: @actor)
    assert_nil repo.active

    Repository.restore(repo.id, actor: @actor)
    assert repo.reload.active
  end

  test "skips synchronize_search_index" do
    Repository.any_instance.expects(:synchronize_search_index).times(0)
    Repository.restore(@archived.id, actor: @actor)
  end

  context "has safety checks" do
    test "soft-deleted: restore fails if the restored nwo is retired and owner_id doesn't match" do
      GitHub.flipper[:disallow_retired_namespace_restores].enable

      # 91 days ago, the victim's account was deleted, so the username is now available
      travel_to (ReservedLogin::DEFAULT_TOMBSTONE_EXPIRY + 1.day).ago do
        victim = create(:user, login: "victim")

        # victim creates popular repo python-package, retires it
        create(:retired_namespace, owner: victim, name: "python-package")

        # destroy the account, tombstone is created that expires in 90 days
        victim.destroy!
      end

      # attacker creates attacker/python-package
      attacker = create(:user, login: "attacker")
      repo = create(:repository, owner: attacker, name: "python-package")

      # attacker deletes attacker/python-package
      repo.update!(active: false)

      # attacker renames to victim
      attacker.update!(login: "victim")

      # attacker attempts to restore repo to victim/python-package
      Repository.restore(repo.id, actor: attacker)

      refute Repository.exists?(owner_login: "victim", name: "python-package"), "victim/python-package repo should not exist"
    end

    test "soft-deleted: restore succeeds if the restored nwo is retired and owner_id matches" do
      GitHub.flipper[:disallow_retired_namespace_restores].enable

      innocent = create(:user, login: "innocent")

      # innocent creates popular repo python-package, retires it
      repo = create(:repository, owner: innocent, name: "python-package")
      create(:retired_namespace, owner: innocent, name: "python-package")

      # soft deletion
      repo.update!(active: false, deleted_at: Time.now)

      refute Repository.exists?(active: true, owner_login: "innocent", name: "python-package"), "repo should have been archived"

      # innocent attempts to restore repo to innocent/python-package
      Repository.restore(repo.id, actor: innocent)

      assert Repository.exists?(active: true, owner_login: "innocent", name: "python-package"), "original owner should be able to reclaim repo"
    end

    test "archived: restore fails if the restored nwo is retired and owner_id doesn't match" do
      GitHub.flipper[:disallow_retired_namespace_restores].enable

      # 91 days ago, the victim's account was deleted, so the username is now available
      travel_to (ReservedLogin::DEFAULT_TOMBSTONE_EXPIRY + 1.day).ago do
        victim = create(:user, login: "victim")

        # victim creates popular repo python-package, retires it
        create(:retired_namespace, owner: victim, name: "python-package")

        # destroy the account, tombstone is created that expires in 90 days
        victim.destroy!
      end

      # attacker creates attacker/python-package
      attacker = create(:user, login: "attacker")
      repo = create(:repository, owner: attacker, name: "python-package")

      # attacker deletes attacker/python-package
      repo.remove(repo.owner)

      # attacker renames to victim
      attacker.update!(login: "victim")

      # attacker attempts to restore repo to victim/python-package
      Repository.restore(repo.id, actor: attacker)

      refute Repository.exists?(owner_login: "victim", name: "python-package"), "victim/python-package repo should not exist"
    end

    test "deleted: restore succeeds if the restored nwo is retired and owner_id matches" do
      GitHub.flipper[:disallow_retired_namespace_restores].enable

      innocent = create(:user, login: "innocent")

      # innocent creates popular repo python-package, retires it
      repo = create(:repository, owner: innocent, name: "python-package")
      create(:retired_namespace, owner: innocent, name: "python-package")
      repo.remove(repo.owner)

      assert repo.reload.deleted?, "repo should have been deleted"

      # innocent attempts to restore repo to innocent/python-package
      Repository.restore(repo.id, actor: innocent)

      assert Repository.exists?(owner_login: "innocent", name: "python-package"), "original owner should be able to reclaim repo"
    end

    test "restore fails if repo exists" do
      GitHub.context.push(from: "stafftools/purgatory#restore")
      repo = create :repository, owner: @user

      refute Repository.restore(repo.id, actor: @actor)
      assert Repository.any_instance.expects(:unhide).never
    end

    test "cannot restore repository with the same name as an existing repository" do
      GitHub.context.push(from: "stafftools/purgatory#restore")
      repo = create :repository, owner: @user, name: @archived.name
      restored = Repository.restore(@archived.id, actor: @actor)
      refute restored
      assert Repository.any_instance.expects(:unhide).never
    end

    test "cannot restore if owner is an org and it is soft deleted" do
      GitHub.flipper[:soft_delete_organization].enable

      org = create :organization

      GitHub.context.push(from: "stafftools/purgatory#restore")
      repo = create :repository, owner: org
      org.soft_delete!

      refute Repository.can_restore?(repo)
      assert repo.errors.messages, { deleted_owner: ["Repository belongs to a deleted organization."] }
    end
  end

  test "restore fails if fork exists in network" do
    GitHub.context.push(from: "stafftools/purgatory#restore")
    repo = create :repository, owner: @actor
    RepositoryNetwork.any_instance.stubs(:root).returns(repo)
    RepositoryNetwork.any_instance.stubs(:find_fork_for).returns(repo)
    refute Repository.restore(@archived.id, actor: @actor)
    assert Repository.any_instance.expects(:unhide).never
  end

  test "restore recalculates network counts" do
    repo = create(:public_repository, owner: @org)
    forked = create(:public_repository, owner: @actor, parent: repo)
    inline_remove(forked, remover: @actor)
    assert_equal repo.reload.public_fork_count, 0

    Repository.restore(forked.id, actor: @actor)
    assert_equal repo.reload.public_fork_count, 1
  end

  test "cannot restore repository without archive" do
    @archived.destroy

    assert_raises(ActiveRecord::RecordNotFound) do
      Repository.restore(@archived.id, actor: @actor)
    end
  end

  context "with packages" do
    test "restores packages deleted from repo deletion" do
      repo = create :repository, owner: @user
      create :registry_package, repository: repo

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 17) do
        inline_remove(repo, remover: @actor)
      end

      assert repo.packages.first.deleted?

      perform_enqueued_hydro_jobs(only: [HydroRestorePackagesRepositoryRestoreJob], allowed_primary_query_count: 23) do
        Repository.restore(repo.id, actor: @actor)
      end

      refute repo.packages.first.deleted?
    end

    test "does not restore packages deleted before the repo was deleted" do
      repo = create :repository, owner: @user
      create :registry_package, repository: repo

      repo.packages.first.delete!
      assert repo.packages.first.deleted?

      inline_remove(repo, remover: @actor)

      perform_enqueued_hydro_jobs(only: [HydroRestorePackagesRepositoryRestoreJob], allowed_primary_query_count: 3) do
        Repository.restore(repo.id, actor: @actor)
      end

      # Package should remain deleted even after repo restore
      assert repo.packages.first.deleted?
    end

    test "deletes other packages when one raises PackageConflictError" do
      repo = create :repository, owner: @user
      error_package = create :registry_package, repository: repo
      restoreable_package = create :registry_package, repository: repo

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 34) do
        inline_remove(repo, remover: @actor)
      end

      assert repo.packages.all?(&:deleted?)

      # Create a duplicate to induce a PackageConflictError
      duplicate_package = create(:registry_package,
        repository: repo,
        name: error_package.name,
        package_type: error_package.package_type
      )

      perform_enqueued_hydro_jobs(only: [HydroRestorePackagesRepositoryRestoreJob], allowed_primary_query_count: 24) do
        Repository.restore(repo.id, actor: @actor)
      end

      repo.reload
      assert repo.packages.first.deleted?
      refute repo.packages.second.deleted?
    end

    test "deletes other packages when one raises PackageDeletionError" do
      repo = create :repository, owner: @user
      error_package = create :registry_package, repository: repo
      restoreable_package = create :registry_package, repository: repo

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 34) do
        inline_remove(repo, remover: @actor)
      end

      assert repo.packages.all?(&:deleted?)

      # Create a duplicate to induce a PackageConflictError
      repo.update(deleted_at: 40.days.ago)
      error_package.update(deleted_at: 35.days.ago)

      perform_enqueued_hydro_jobs(only: [HydroRestorePackagesRepositoryRestoreJob], allowed_primary_query_count: 24) do
        Repository.restore(repo.id, actor: @actor)
      end

      repo.reload
      assert repo.packages.first.deleted?
      refute repo.packages.second.deleted?
    end

    test "proceeds with repo restoration if package restoration fails" do
      repo = create :repository, owner: @user
      create :registry_package, repository: repo

      perform_enqueued_hydro_jobs(only: [HydroDeletePackagesRepositoryDeletedJob], allowed_primary_query_count: 17) do
        inline_remove(repo, remover: @actor)
      end

      assert repo.packages.first.deleted?

      Repository.any_instance.stubs(:packages).raises(StandardError)

      restored = Repository.restore(repo.id, actor: @actor)

      Repository.any_instance.unstub(:packages)
      # The package will remain deleted
      assert repo.packages.first.deleted?
      # But the repo is still successfully restored
      assert restored.active
    end
  end

  context "with two factor violations" do
    test "does not restore outside collaborators who have disabled two factor" do
      GitHub.flipper[:members_without_2fa_allowed].disable
      GitHub.flipper[:two_factor_cap_enforcement].disable
      @org.enable_two_factor_requirement(actor: @org.owner)
      repo = create(:private_repository, owner: @org)
      outside_collaborator = create(:two_factor_credential_user)
      repo.add_member(outside_collaborator)

      assert_equal 1, repo.members.count

      inline_remove(repo, remover: @actor)
      outside_collaborator.two_factor_credential.destroy
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 0, restored.members.count
    end

    test "does not restore outside collaborators who do not meet org two factor requirement" do
      GitHub.flipper[:members_without_2fa_allowed].disable
      GitHub.flipper[:two_factor_cap_enforcement].disable
      repo = create(:private_repository, owner: @org)
      outside_collaborator = create(:user)
      repo.add_member(outside_collaborator)

      assert_equal 1, repo.members.count

      inline_remove(repo, remover: @actor)
      @org.enable_two_factor_requirement(actor: @org.owner)
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 0, restored.members.count
    end

    test "restores outside collaborators if the org has not enabled two factor" do
      repo = create(:private_repository, owner: @org)
      outside_collaborator = create(:user)
      repo.add_member(outside_collaborator)
      inline_remove(repo, remover: @actor)
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 1, restored.members.count
    end

    test "restores outside collaborators if the org enforces 2FA but allows members without 2fa" do
      GitHub.flipper[:members_without_2fa_allowed].enable
      GitHub.flipper[:two_factor_cap_enforcement].enable
      repo = create(:private_repository, owner: @org)
      outside_collaborator = create(:user)
      repo.add_member(outside_collaborator)

      assert_equal 1, repo.members.count

      inline_remove(repo, remover: @actor)
      @org.enable_two_factor_requirement(actor: @org.owner)
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 1, restored.members.count
    end

    test "restores outside collaborators to non-org repo" do
      repo = create(:private_repository, owner: @actor)
      outside_collaborator = create(:user)
      repo.add_member(outside_collaborator)
      inline_remove(repo, remover: @actor)
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 1, restored.members.count
    end

    test "restores outside collaborators who meet two factor requirement" do
      @org.enable_two_factor_requirement(actor: @org.owner)
      repo = create(:private_repository, owner: @org)
      outside_collaborator = create(:two_factor_credential_user)
      repo.add_member(outside_collaborator)
      inline_remove(repo, remover: @actor)
      restored = Repository.restore(repo.id, actor: @actor)

      assert_equal 1, restored.members.count
    end
  end

  context "instruments restores from staff settings" do
    test "includes actor for instrumentation when given" do
      GitHub.context.push(from: "stafftools/purgatory#restore")
      events = subscribe "staff.repo_restore"

      if GitHub.guard_audit_log_staff_actor?
        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          staff_actor: @actor.login,
          staff_actor_id: @actor.id,
          repo: @archived.name_with_owner,
          repo_id: @archived.id,
          public_repo: @archived.public?,
          actor: User.staff_user.login,
          actor_id: User.staff_user.id,
        }
      else
        expected_payload = {
          user: @user.login,
          user_id: @user.id,
          actor: @actor.login,
          actor_id: @actor.id,
          repo: @archived.name_with_owner,
          repo_id: @archived.id,
          public_repo: @archived.public?,
        }
      end

      Repository.restore(@archived.id, actor: @actor)
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "includes correct instrumentation payload when restore initiated by user" do
      GitHub.context.push(from: "repos/restore#restore")
      events = subscribe "repo.restore"

      expected_payload = {
        actor: @actor.login,
        actor_id: @actor.id,
        user: @user.login,
        user_id: @user.id,
        repo: @archived.name_with_owner,
        repo_id: @archived.id,
        public_repo: @archived.public?,
      }

      Repository.restore(@archived.id, actor: @actor)
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "won't restore an unrestorable repository" do
      repo = create :repository, owner: @user
      GitHub.flipper[:advisory_db_unrestorable_repositories].enable repo
      inline_remove(repo)

      # We expect this line to succeed, it's the base case for the next part of our test
      Repository.restore(repo.id, actor: @actor, synchronous: true)
      repo.reload
      refute repo.deleted?

      repo = create :repository, owner: @user
      GitHub.flipper[:advisory_db_unrestorable_repositories].enable repo
      repo.restorable = false
      repo.save!
      inline_remove(repo)

      Repository.restore(repo.id, actor: @actor, synchronous: true)
      repo.reload
      assert repo.deleted?
    end

    test "enqueues a hydro message on restore", skip_enterprise: true do
      Timecop.freeze do
        Repository.restore(@archived.id, actor: @actor)

        repo = Repository.where(name: @archived.name).first
        assert_hydro_published({
          restored_repository: Hydro::EntitySerializer.repository(repo),
          actor: Hydro::EntitySerializer.user(@actor),
          }, schema: "github.v1.RepositoryRestored", ignore_extra_keys: true)
        assert_hydro_messages(count: 1, schema: "github.v1.RepositoryRestored")
      end
    end

    if !TestEnv.test_all_features?
      test "enqueues a hydro message on restore search indexing", skip_enterprise: true do
        Timecop.freeze do
          repo = create :repository, owner: @user, from_example: :simple
          repo.initialize_wiki(repo.owner)
          example_repo :wiki, repo.unsullied_wiki
          issue = create :issue, repository: repo, user: @user

          inline_remove(repo, remover: @user)
          assert_hydro_published({
            change: :DELETED,
            repository: Hydro::EntitySerializer.repository(repo),
            ref: "refs/heads/#{repo.default_branch}",
            owner_name: repo.owner.name,
          }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)
          assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")

          GitHub.hydro_publisher.sink&.messages&.clear

          Repository.restore(repo.id, actor: @actor)

          restored_repo = Repositories::Public.find_active(repo.id)
          assert_hydro_published({
            change: :RESTORED,
            repository: Hydro::EntitySerializer.repository(restored_repo),
            ref: "refs/heads/#{restored_repo.default_branch}",
            owner_name: restored_repo.owner.name,
          }, schema: "github.search.v0.RepositoryChanged", ignore_extra_keys: true)
          assert_hydro_messages(count: 1, schema: "github.search.v0.RepositoryChanged")
        end
      end
    end
  end
end
