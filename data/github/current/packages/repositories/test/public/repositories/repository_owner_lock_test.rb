# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoriesRepositoryOwnerLockTest < Api::TestCase

  fixtures do
    @owner = create(:user)
    @repository = create(:repository, owner: @owner)
  end

  teardown do
    Repositories::RepositoryOwnerLock.release_rename_lock(owner_id: @owner.id)
  end

  [:with_rename_lock, :with_rename_lock!].each do |method|
    context "##{method}" do
      test "returns true if lock is acquired" do
        # Ensure it is not locked
        refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repository.owner.id)

        result = Repositories::RepositoryOwnerLock.send(method, owner_id: @owner.id) do
          assert Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repository.owner.id)
          assert Repositories::RepositoryOwnerLock.send(:rename_mutex, owner_id: @owner.id).locked?
        end

        refute Repositories::RepositoryOwnerLock.send(:rename_mutex, owner_id: @owner.id).locked?

        assert result
      end

      test "returns false if lock is not acquired" do
        # acquire lock
        assert Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: @repository.owner.id)

        refute Repositories::RepositoryOwnerLock.send(method, owner_id: @owner.id) { raise "This block shouldn't be called" }
      end

      test "graceful degradation" do
        Repositories::Redis.stubs(:mutex).raises("boom")

        if method.to_s.ends_with?("!")
          assert_raises(RuntimeError) do
            Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id) { raise "This block shouldn't be called" }
          end
        else
          execution_count = 0

          result = Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id) do
            execution_count += 1
          end

          assert_equal 1, execution_count
          assert result
        end

      ensure
        Repositories::Redis.unstub(:mutex)
      end
    end
  end

  [:acquire_rename_lock, :acquire_rename_lock!].each do |method|
    context "##{method}" do
      test "returns true if lock is acquired" do
        # Ensure it is not locked
        refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repository.owner.id)
        assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
        assert Repositories::RepositoryOwnerLock.send(:rename_mutex, owner_id: @owner.id).locked?
      end

      test "returns false if lock is not acquired" do
        assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
        refute Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
      end

      test "graceful degradation" do
        Repositories::Redis.stubs(:mutex).raises("boom")

        if method.to_s.ends_with?("!")
          assert_raises(RuntimeError) do
            Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
          end
        else
          assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
        end

      ensure
        Repositories::Redis.unstub(:mutex)
      end
    end
  end

  context "#locked_for_rename?" do
    test "returns true if lock is acquired" do
      assert Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: @repository.owner.id)

      # Ensure it is not locked
      assert Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repository.owner.id)
    end

    test "returns false if lock is not acquired" do
      # Ensure it is not locked
      refute Repositories::RepositoryOwnerLock.locked_for_rename?(owner_id: @repository.owner.id)
    end
  end

  [:release_rename_lock, :release_rename_lock!].each do |method|
    context "##{method}" do
      test "releases the lock" do
        assert Repositories::RepositoryOwnerLock.acquire_rename_lock(owner_id: @repository.owner.id)

        assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)

        refute Repositories::RepositoryOwnerLock.send(:rename_mutex, owner_id: @owner.id).locked?
      end

      test "does not fail if lock is not acquired" do
        assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
      end

      test "graceful degradation" do
        Repositories::Redis.stubs(:mutex).raises("boom")

        if method.to_s.ends_with?("!")
          assert_raises(RuntimeError) do
            Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
          end
        else
          assert Repositories::RepositoryOwnerLock.send(method, owner_id: @repository.owner.id)
        end

      ensure
        Repositories::Redis.unstub(:mutex)
      end

    end
  end
end
