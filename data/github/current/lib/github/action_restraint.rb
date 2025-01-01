# typed: true
# frozen_string_literal: true

module GitHub
  module ActionRestraint
    KV_LOCK_EXPIRATION = 1.minute
    RESTRAINT_NAME_MAX_LENGTH = 64
    #  Public: Checks to see if we should perform an action.
    #
    #  base_key   - The String for the action we are checking
    #  interval   - The Duration specifying how often we should perform the
    #               action.
    #  extra_keys - The Hash of additional keys/value that, in combination with
    #               the base_key, uniquely identify the action we are checking.
    #
    #  Returns a boolean for whether to perform the action or not.
    def self.perform?(base_key, interval:, **extra_keys)

      # disallow folks from setting an interval of less than 1 minute (or whatever we pick
      # for the kv lock expiration value) as we are using a temperory setnx to ensure there
      # is no race condition as only one caller will obtain the lock.
      if interval < KV_LOCK_EXPIRATION
        raise ArgumentError.new("please use an interval larger than #{KV_LOCK_EXPIRATION}")
      end

      if base_key.length > RESTRAINT_NAME_MAX_LENGTH
        raise ArgumentError, "base_key cannot be longer than #{RESTRAINT_NAME_MAX_LENGTH} characters"
      end

      key = restraint_key(base_key, extra_keys)
      return false if recently_performed?(key, interval)

      # If we have not returned early we know it is time to perform the action.
      # To ensure only one caller actually performs the action, we need to
      # ensure only one caller obtains the lock to update the associated KV
      # entry that tracks when the action was last performed.
      #
      # We use setnx to account for race conditions with multiple callers when
      # it is time to update the last performed timestamp in KV. If we have two
      # requests that reach this point we assure ourselves that only one of them
      # will successfully invoke `setnx`. The caller to obtain the lock will
      # then be the one to perform the action and update the last performed
      # timestamp.
      lock_key = restraint_lock_key(key)

      # This arbitrary 1.minute expiration vaguely implies we shouldn't
      # let folks set an interval of less than 1 minute (or whatever we pick
      # here) for the overall  interval rate. we are raising an argument error
      # if we see someone try to ensure folks understand.
      GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:action_restraint"])
      lock_obtained = ActiveRecord::Base.connected_to(role: :writing) do
        GitHub::Authentication::KV.store.setnx(lock_key, "true", expires: KV_LOCK_EXPIRATION.from_now)
      end

      if lock_obtained
        # We know that at this point a single caller has obtained the update
        # lock and is the caller we will tell to perform the action. But, first,
        # we need to update the last performed timestamp in KV.
        now = Time.now.to_i
        GitHub.dogstats.increment("authn_kv", tags: ["action:write", "callsite:action_restraint"])
        ActiveRecord::Base.connected_to(role: :writing) do
          GitHub::Authentication::KV.store.set(key, now.to_s, expires: interval.from_now)
        end
        # We also update memcache to save an unnecessary cache miss for future
        # callers. As has been stated throughout this module, we explicitly do
        # not rely on the update to memcache being globally consisent. Once we
        # update KV, the other DCs will realize their memcache entries are stale
        # (inside of `recently_performed?`) and update them to be consistent
        # with whatever is in KV.
        GitHub.cache.set(key, now)
        true
      else
        # The caller failed to obtain the update lock and and is not the caller
        # that we will tell to perform the action (or update KV/memcache).
        false
      end
    end

    #  Public: Checks to see if we recently performed the associated action
    #  for `key`
    #
    #  key      - The String value for the action we are checking.
    #  interval - The Duration specifying how often we should perform the
    #             action.
    #
    #  Returns a boolean for whether the action was recently performed or not.
    def self.recently_performed?(key, interval)
      # Use a fixed value for "now" throughout this method because we want a
      # consistent value used for doing various operations with time.
      last_check_cutoff = interval.ago.to_i
      # First check with the local DC memcache cluster to see if we have the
      # last time this action was performed. We explicitly do not rely on
      # this value being globally consistent across DCs. Because we are storing
      # a timestamp, we can check for whether the value returned by the local DC
      # memcache cluster is "current" or if it might be stale and should be
      # updated.
      last_performed = GitHub.cache.get(key)

      # If we found a value in the cache we check to see if it is time to
      # perform the action.
      if last_performed
        # This is the hot path. Typically `interval` is measured in days, weeks,
        # or months. As a result, we expect that the vast majority of time, at
        # least for chatty clients, we will have the value in the cache, and we
        # can return early.
        recently_performed = last_performed.to_i > last_check_cutoff
        return true if recently_performed
      end

      # If we did not return early above, we know that either `last_performed`
      # was `nil` OR it was not `nil` and the cache is telling us the action was
      # not recently performed. In either case, we want to check with KV to
      # obtain an authoritative answer for whether we actually did or didn't
      # recently perform the action.
      GitHub.dogstats.increment("authn_kv", tags: ["action:read", "callsite:action_restraint"])
      last_performed = GitHub::Authentication::KV.store.get(key).value { nil }

      # If we found a value in KV we check to see if it is time to perform the
      # action. We can't assume the only time it is time to perform an action is
      # when the KV entry expires and is missing.  If `interval` changed we may
      # still have data in KV, but it may still be time to perform the action
      # again. For example, if interval changed from 1.month to 1.week we might
      # have existing data in KV, three weeks have passsed, and it time to
      # perform according to the new interval.
      if last_performed
        recently_performed = last_performed.to_i > last_check_cutoff
        # If we find out that we have already recently performed this action,
        # that means our cache entry in this DC is stale. We update the cache
        # for this DC and return. We explicitly do not rely on this value being
        # globally consistent across DCs. Each server serving traffic will
        # perform the same logic we are performing here and will update the
        # local DC memcache entry when needed.
        if recently_performed
          GitHub.cache.set(key, last_performed.to_i)
          return true
        end
      end
      false
    end

    #  Public: Generates the unique key for checking whether a given action
    #  was performed recently.
    #
    #  base_key   - The String that specifies the action.
    #  extra_keys - The Hash of additional keys/value that, in combination with
    #               the base_key, uniquely identify the action.
    #
    #  Returns a String that uniquely identifies the action we are performing.
    def self.restraint_key(base_key, extra_keys)
      [
        base_key,
        Digest::SHA256.hexdigest(extra_keys.keys.sort.map { |k| "#{k}:#{extra_keys[k]}" }.join),
      ].join(":")
    end

    #  Public: Generates the unique lock key for updating the KV entry for the
    #  action we are performing.
    #
    #  restraint_key - The String that uniquely identifies the action we want to
    #                  update.
    #
    #  Returns a String that uniquely identifies the update lock for the action
    #  we are updating.
    def self.restraint_lock_key(restraint_key)
      [
        T.unsafe(self).name.demodulize.underscore,
        "restraint_lock_key",
        restraint_key,
      ].join(":")
    end
  end
end
