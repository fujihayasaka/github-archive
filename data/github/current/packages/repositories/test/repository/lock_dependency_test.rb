# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryLockDependencyTest < GitHub::TestCase
  fixtures do
    @defunkt  = create(:user, login: "defunkt",  plan: "medium")
    @maddox   = create(:user, login: "maddox")
    @mojombo  = create(:user, login: "mojombo2", plan: "medium")

    @ambition = create(:private_repository, name: "ambition", owner: @defunkt)
    @grit     = create(:repository, name: "grit",     owner: @mojombo)
    @simple   = create(:repository, name: "simple",   owner: @defunkt)
  end

  test "lock_including_forks and unlock_including_forks apply to forks" do
    fork = create(:fork_repository, forker: create(:user), fork_repo: @simple)
    @simple.lock_including_descendants!
    assert @simple.locked
    assert fork.reload.locked

    @simple.unlock_including_descendants!
    refute @simple.locked
    refute fork.reload.locked
  end

  test "a repo can be locked for billing reasons" do
    @ambition.lock_for_billing

    assert_equal @ambition.lock_reason, Repository::LockDependency::BILLING
    assert @ambition.locked_on_billing?
    assert @ambition.locked?
  end

  test "a repo can be locked for trade restriction reasons" do
    @ambition.lock_for_trade_restriction

    assert_equal @ambition.lock_reason, Repository::LockDependency::TRADE_RESTRICTION
    assert @ambition.locked_on_trade_restriction?
    assert @ambition.locked?
  end

  test "a repo can be locked because it doesn't exist on disk" do
    @ambition.stubs(:exists_on_disk?).returns(false)
    @ambition.lock_including_descendants!

    assert @ambition.locked_on_disk?
    assert @ambition.locked?
  end

  test "a repo can be locked because it is moving to a new network" do
    @ambition.lock_for_move

    assert_equal @ambition.lock_reason, Repository::LockDependency::MOVING
    assert @ambition.locked_on_move?
    assert @ambition.locked?
  end

  test "locking with invalid reason raises a ArgumentError" do
    assert_raises(ArgumentError) { @ambition.lock!("whatever") }
    assert_raises(ArgumentError) { @ambition.lock_excluding_descendants!("whatever") }
    assert_raises(ArgumentError) { @ambition.lock_including_descendants!("whatever") }

    @ambition.reload
    refute @ambition.locked?
    assert_nil @ambition.lock_reason
  end

  test "locking works for valid reasons" do
    Repository::LockDependency::REPOSITORY_LOCK_REASONS.each do |reason|
      @ambition.lock!(reason)
      assert_equal @ambition.lock_reason, reason
      assert @ambition.locked

      # Revert lock state
      @ambition.update(locked: false, lock_reason: nil)
      assert_nil @ambition.lock_reason
      refute @ambition.locked
    end
  end

  test "locking works when lock_reason is nil" do
    @ambition.lock!(nil)
    assert_nil @ambition.lock_reason
    assert @ambition.locked
  end

  test "a repo can be locked without locking forks while being migrated to a new GitHub instance" do
    fork = create(:fork_repository, forker: create(:user), fork_repo: @simple)
    @simple.lock_for_migration

    assert @simple.locked
    assert_equal @simple.lock_reason, Repository::LockDependency::MIGRATING
    refute fork.reload.locked

    @simple.unlock_excluding_descendants!
    refute @simple.locked
  end

  test "lock_excluding_descendants! creates audit log entry with staff_user and actor" do
    events = subscribe "staff.repo_lock"
    @simple.lock_excluding_descendants!
    assert @simple.locked

    assert event = events.pop, "an audit event was expected"
    assert_equal "staff.repo_lock", event.name
    refute_nil event.payload[:actor_id]
    # enterprise doesn't have "staff_actor_id"
    refute_nil event.payload[:staff_actor_id] unless GitHub.enterprise?
  end

  test "unlock_excluding_descendants! creates audit log entry with staff_user and actor" do
    events = subscribe "staff.repo_lock"
    @simple.lock_for_migration
    assert @simple.locked
    @simple.unlock_excluding_descendants!

    assert event = events.pop, "an audit event was expected"
    assert_equal "staff.repo_lock", event.name
    refute_nil event.payload[:actor_id]
    # enterprise doesn't have "staff_actor_id"
    refute_nil event.payload[:staff_actor_id] unless GitHub.enterprise?
  end

  test "a lock reason is propagated to forks and forks of forks" do
    @fork = create(:fork_repository, forker: @mojombo, fork_repo: @grit)
    @fork_of_fork = create(:fork_repository, forker: @maddox, fork_repo: @fork)
    @grit.lock_for_move

    assert @grit.reload.locked_on_move?
    assert_equal @grit.reload.lock_reason, Repository::LockDependency::MOVING
    assert @fork.reload.locked_on_move?
    assert_equal @fork.reload.lock_reason, Repository::LockDependency::MOVING
    assert @fork_of_fork.reload.locked_on_move?
    assert_equal @fork_of_fork.reload.lock_reason, Repository::LockDependency::MOVING
  end
end
