# typed: strict
# frozen_string_literal: true

module Repositories
  module RepositoryOwnerLock
    extend self
    extend T::Sig

    include Kernel

    sig { params(owner_id: Integer, block: T::proc.returns(T.untyped)).returns(T::Boolean) }
    def with_rename_lock(owner_id:, &block)
      GitHub::Result.new { with_rename_lock!(owner_id:, &block) }.rescue do |e|
        GitHub.logger.info(
          "Something went wrong while acquiring rename lock in Redis. Gracefully degrading.",
          { "gh.request_id" => GitHub.context[:request_id], "user.id" => owner_id, "exception" => e }
        )
        GitHub::Result.error(e)
      end.value do
        block.call
        true
      end
    end

    sig { params(owner_id: Integer, block: T::proc.returns(T.untyped)).returns(T::Boolean) }
    def with_rename_lock!(owner_id:, &block)
      begin
        rename_mutex(owner_id:).lock do
          block.call
        end
        return true
      rescue GitHub::Redis::Mutex::LockError => e
        GitHub.logger.info(
          "Failed to acquire rename lock in Redis",
          { "gh.request_id" => GitHub.context[:request_id], "user.id" => owner_id, "exception" => e }
        )
      end

      false
    end

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def acquire_rename_lock(owner_id:)
      GitHub::Result.new { acquire_rename_lock!(owner_id:) }.rescue do |e|
        GitHub.logger.info(
          "Something went wrong while acquiring rename lock in Redis. Gracefully degrading.",
          { "gh.request_id" => GitHub.context[:request_id], "user.id" => owner_id, "exception" => e }
        )
        GitHub::Result.error(e)
      end.value { true }
    end

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def acquire_rename_lock!(owner_id:)
      begin
        rename_mutex(owner_id:).lock
        return true
      rescue GitHub::Redis::Mutex::LockError => e
        # we will return false below if we can't acquire the lock
      end
      false
    end

    sig { params(owner_id: Integer).returns(T::Boolean) }
    def locked_for_rename?(owner_id:)
      rename_mutex(owner_id:).locked?
    end

    sig { params(owner_id: Integer).void }
    def release_rename_lock(owner_id:)
      GitHub::Result.new { release_rename_lock!(owner_id:) }.rescue do |e|
        GitHub.logger.info("Something went wrong while releasing rename lock in Redis. Gracefully degrading.",
          { "gh.request_id" => GitHub.context[:request_id], "user.id" => owner_id, "exception" => e }
        )
        GitHub::Result.error(e)
      end.value { nil }
    end

    sig { params(owner_id: Integer).void }
    def release_rename_lock!(owner_id:)
      rename_mutex(owner_id:).unlock!
    end

    private

    sig { params(owner_id: Integer).returns(String) }
    def rename_lock_key(owner_id:)
      "repo-owner-rename-lock-#{owner_id}"
    end

    sig { params(owner_id: Integer).returns(GitHub::Redis::ConcurrencySafeMutex) }
    def rename_mutex(owner_id:)
      mutex(key: rename_lock_key(owner_id:), timeout_sec: 20.seconds)
    end

    sig { params(key: String, timeout_sec: Integer).returns(GitHub::Redis::ConcurrencySafeMutex) }
    def mutex(key:, timeout_sec:)
      Repositories::Redis.mutex(key: key, timeout_sec: timeout_sec)
    end

  end
end
