# typed: true
# frozen_string_literal: true

module LastAccessible
  extend T::Helpers

  # One week was decided back in https://github.com/github/github/pull/76724
  # to reduce the number of writes.
  ACCESS_THROTTLING = 1.week

  # Internal: The amount of time desired between writes to the `accessed_at`
  # column.
  #
  # Returns an ActiveSupport::Duration
  def access_throttling
    ACCESS_THROTTLING
  end

  # Internal: Has this access been used in the throttling period.
  #
  # Returns a Boolean.
  def bumped_within_throttling_period?
    T.bind(self, UserProgrammaticAccess)
    return false if accessed_at.nil?

    T.must(accessed_at) > (Time.zone.now - access_throttling)
  end

  # Public: Enqueue a background job to update the `accessed_at` column
  # on the record.
  #
  # This method will only enqueue the job if we're outside the throttling
  # period (see ACCESS_THROTTLING). This is to ensure we don't cause a huge
  # amounts of writes for active tokens.
  #
  # Returns nothing.
  def bump
    return if bumped_within_throttling_period?
    now = Time.zone.now

    if unlocked?(last_accessed_memcache_key, now)
      ProgrammaticAccessBumpJob.perform_later(self, now)
    end
  end

  # Public: Update the accessed_at time for a ProgrammaticAccess.
  #
  # time - The ActiveSupport::TimeWithZone the ProgrammaticAccess was last
  #        used.
  #
  # Returns nothing.
  # Raises ActiveRecord::RecordInvalid if the access failed to be updated.
  def bump!(time)
    return if bumped_within_throttling_period?

    T.bind(self, UserProgrammaticAccess)

    ActiveRecord::Base.connected_to(role: :writing) do
      self.update!(accessed_at: time)
    end
  end

  # Internal: The key used in memcache to help prevent unneccessary writes.
  #
  # Examples
  #
  #   last_accessed_memcache_key
  #   => "last_accessed:8e1c09ffe40bf84374684304ce046ebd083d5f2e82fa307e0fac546f9433b2a7"
  #
  # Returns a String.
  def last_accessed_memcache_key
    T.bind(self, UserProgrammaticAccess)

    suffix = Digest::SHA256.hexdigest("#{T.must(self.class.name).underscore}:#{self.id}")
    "last_accessed:#{suffix}"
  end

  # Internal: Has this job not been enqueued in the last week?
  #
  # key  - The String representing the memcached key.
  # time - The ActiveSupport::TimeWithZone representing the memcached value.
  #
  # Returns true if all of the caches were able to be written to, otherwise
  #   false.
  def unlocked?(key, time)
    ttl = ACCESS_THROTTLING.to_i

    caches = [GitHub.cache, *GitHub.regional_caches.values]
    caches.all? { |cache| cache.add(key, time, ttl) }
  end
end
