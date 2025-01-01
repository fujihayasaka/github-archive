# frozen_string_literal: true

require "test_helper"
require "advisory_db/lock"

module AdvisoryDB
  class LockTest < ActiveSupport::TestCase
    test "requires a string key" do
      assert_raise ArgumentError do
        Lock.new(:foo)
      end

      assert_nothing_raised do
        Lock.new("foo")
      end
    end

    test "requires an integer TTL" do
      assert_raise ArgumentError do
        Lock.new("foo", ttl: 123.45)
      end

      assert_nothing_raised do
        Lock.new("foo", ttl: 123)
      end
    end

    test "requires a positive TTL" do
      assert_raise ArgumentError do
        Lock.new("foo", ttl: -123)
      end
    end

    test "tracks its own locked/unlocked status" do
      lock = Lock.new("foo")

      refute lock.locked?
      assert lock.unlocked?

      lock.lock

      assert lock.locked?
      refute lock.unlocked?

      lock.unlock

      refute lock.locked?
      assert lock.unlocked?
    end

    test "shares its status with identically-keyed locks" do
      lock_1 = Lock.new("foo")
      lock_2 = Lock.new("foo")
      lock_3 = Lock.new("bar")

      refute lock_1.locked?
      assert lock_1.unlocked?
      refute lock_1.mine?

      refute lock_2.locked?
      assert lock_2.unlocked?
      refute lock_2.mine?

      refute lock_3.locked?
      assert lock_3.unlocked?
      refute lock_3.mine?

      lock_1.lock

      assert lock_1.locked?
      refute lock_1.unlocked?
      assert lock_1.mine?

      assert lock_2.locked?
      refute lock_2.unlocked?
      refute lock_2.mine?

      refute lock_3.locked?
      assert lock_3.unlocked?
      refute lock_3.mine?
    end

    test "knows when the lock was locked" do
      lock = Lock.new("foo")

      assert_nil lock.locked_at

      now = Time.current
      lock.lock

      refute_nil lock.locked_at
      assert_kind_of Time, lock.locked_at
      assert_in_delta now, lock.locked_at, 1.second

      lock.unlock

      assert_nil lock.locked_at
    end

    test "knows how long the lock will be locked" do
      lock = Lock.new("foo", ttl: 42)

      assert_nil lock.expires_in

      lock.lock

      refute_nil lock.expires_in
      assert_kind_of Integer, lock.expires_in
      assert_in_delta 42, lock.expires_in, 1

      lock.unlock

      assert_nil lock.expires_in
    end

    test "knows when the lock will unlock" do
      lock = Lock.new("foo", ttl: 42)

      assert_nil lock.expires_at

      now = Time.current
      lock.lock

      refute_nil lock.expires_at
      assert_kind_of Time, lock.expires_at
      assert_in_delta now + 42.seconds, lock.expires_at, 1.second
    end

    test "wraps locking and unlocking around a block" do
      lock = Lock.new("foo")

      lock.wrap do
        assert lock.locked?
        refute lock.unlocked?
        assert lock.mine?
      end

      refute lock.locked?
      assert lock.unlocked?
      refute lock.mine?

      lock.wrap! do
        assert lock.locked?
        refute lock.unlocked?
        assert lock.mine?
      end

      refute lock.locked?
      assert lock.unlocked?
      refute lock.mine?
    end

    test "can skip the block when wrapping a key that is already locked" do
      Lock.new("foo").lock
      lock = Lock.new("foo")
      block = :skipped

      lock.wrap do
        block = :executed
      end

      assert_equal :skipped, block
      assert lock.locked?
      refute lock.unlocked?
      refute lock.mine?
    end

    test "can raise an error when wrapping a key that is already locked" do
      Lock.new("foo").lock
      lock = Lock.new("foo")
      block = :skipped

      assert_raise Lock::AlreadyLocked do
        lock.wrap! do
          block = :executed
        end
      end

      assert_equal :skipped, block
      assert lock.locked?
      refute lock.unlocked?
      refute lock.mine?
    end

    test "can raise an error when locking a key that is already locked" do
      Lock.new("foo").lock
      lock = Lock.new("foo")

      assert_raise Lock::AlreadyLocked do
        lock.lock!
      end

      assert lock.locked?
      refute lock.unlocked?
      refute lock.mine?
    end

    test "does not complain when unlocking a key that is already unlocked" do
      lock = Lock.new("foo")

      assert_nothing_raised do
        lock.unlock
      end

      refute lock.locked?
      assert lock.unlocked?
    end
  end
end
