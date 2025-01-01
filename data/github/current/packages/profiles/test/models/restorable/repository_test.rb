# typed: true
# frozen_string_literal: true

require "test_helper"

class RestorableRepositoryTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:organization)
    @restorable = Restorable.create
  end

  test ".backup stores restorables into the database" do
    repo = create(:repository, owner: @org)
    assert_difference "Restorable::Repository.count", 1 do
      Restorable::Repository.backup(
                               restorable: @restorable,
                               repositories: [repo],
                             )
    end
  end

  test ".restore restores deleted repositories" do
    # define repo inside test blocks to avoid shared state
    repo = create(:repository, owner: @org)

    Restorable::Repository.create!({
      restorable_id: @restorable.id,
      archived_repository_id: repo.id,
    })

    repo.remove(repo.owner)

    assert Repositories::Public.is_deleted?(repo.id)

    @restorable.expects(:restoring).with(:restorable_repositories).once
    @restorable.expects(:restored).with(:restorable_repositories).once

    Restorable::Repository.restore(restorable: @restorable, organization: @org)

    repo = Repositories::Public.find_active!(repo.id)
    assert_equal repo.owner_id, repo.owner_id
    assert_equal repo.name, repo.name
  end

  test ".restore does not bomb if called twice" do
    # define repo inside test blocks to avoid shared state
    repo = create(:repository, owner: @org)

    Restorable::Repository.create!({
      restorable_id: @restorable.id,
      archived_repository_id: repo.id,
    })
    repo.remove(repo.owner, synchronous: true)

    Restorable::Repository.restore(restorable: @restorable, organization: @org)
    Restorable::Repository.restore(restorable: @restorable, organization: @org)
  end

  test ".restore forks only if the org still owns the network" do
    @org.allow_private_repository_forking(actor: @org.admins.first)

    user = create(:user)
    @org.add_member(user)

    user2 = create(:user)
    @org.add_member(user2)

    root1 = create(:private_repository, owner: @org)
    fork1 = create(:fork_repository, forker: user, fork_repo: root1)

    root2 = create(:private_repository, owner: @org)
    fork2 = create(:fork_repository, forker: user, fork_repo: root2)

    root3 = create(:private_repository, owner: @org)
    fork3 = create(:fork_repository, forker: user, fork_repo: root3)

    assert_equal fork1.organization_id, @org.id
    assert_equal fork2.organization_id, @org.id
    assert_equal fork3.organization_id, @org.id

    Restorable::Repository.create!({ restorable_id: @restorable.id, archived_repository_id: fork1.id })
    Restorable::Repository.create!({ restorable_id: @restorable.id, archived_repository_id: fork2.id })
    Restorable::Repository.create!({ restorable_id: @restorable.id, archived_repository_id: fork3.id })

    # delete the repos
    fork1.remove(user, synchronous: true)
    refute fork1.reload.active?

    fork2.remove(user, synchronous: true)
    refute fork2.reload.active?

    fork3.remove(user, synchronous: true)
    refute fork3.reload.active?

    # fork1: nothing happens to it

    # fork2: the root gets transfered out of the org
    root2.transfer_ownership_to(user2, actor: @org.admin)

    # fork3: a different fork becomes the root
    other_fork = create(:fork_repository, forker: user2, fork_repo: root3)
    ChangeNetworkRootJob.perform_now(other_fork.id)

    assert_equal 3, @restorable.repositories.count

    # attempt to restore all 3 repos. Only the 1st one should be restored
    Restorable::Repository.restore(restorable: @restorable, organization: @org)
    assert fork1.reload.active?
    assert fork2.reload.deleted?
    assert fork3.reload.deleted?
  end
end
