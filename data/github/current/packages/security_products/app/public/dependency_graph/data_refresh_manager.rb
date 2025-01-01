# typed: strict
# frozen_string_literal: true

# This class provides a simple mutex on that only allows one refresh to be requested per repository id every COOLDOWN
# period.
#
# We use this to rate-limit user refreshes to avoid the mechanism being abused since it is a non-trivial process
# that triggers downstream events such as Dependabot Alerts.
module DependencyGraph
  class DataRefreshManager
    include GitHub::Memoizer

    COOLDOWN = T.let(60.minutes, ActiveSupport::Duration)

    sig { params(repository: Repository).void }
    def initialize(repository)
      @repository = repository
    end

    sig { returns(T::Boolean) }
    def on_cooldown?
      mutex.locked?
    end

    sig { params(actor: User).void }
    def request_refresh!(actor:)
      # If we can't immediately get the lock, then we are on cooldown
      return unless mutex.try_lock

      RepositoryDependencyRedetectJob.perform_later(
        @repository.id,
        actor_id: actor.id,
        trigger: :RESET_TRIGGER_USER,
      )
    end

    sig { returns(T::nilable(Time)) }
    def cooldown_ends_at
      return nil unless on_cooldown?

      lock_key = "GitHub::Redis::Mutex-dg:refresh:#{@repository.id}"
      expiry_ts = GitHub.legacy_redis.get(lock_key).to_f

      Time.at(expiry_ts).utc
    rescue ::Redis::CannotConnectError, ::Redis::TimeoutError
      # If we have connectivity issues with Redis, we will failover to a locked
      # state and the UI will try to render this value.
      #
      # Since we cannot determine the real availability, let's be pessimistic
      # and assume the full cooldown remains as a safe degraded state.
      Time.now.utc + COOLDOWN
    end

    private

    sig { returns(GitHub::Redis::Mutex) }
    memoize def mutex
      GitHub::Redis::Mutex.new(
        "dg:refresh:#{@repository.id}",
        timeout: COOLDOWN,
      )
    end
  end
end
