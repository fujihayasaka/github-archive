# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ProgrammaticAccessBumpJob < ApplicationJob
  queue_as :programmatic_access_bumps
  retry_on_dirty_exit

  discard_on ActiveRecord::RecordNotFound

  CACHE_KEY_PREFIX = "github:jobs:programmatic_access_bump"

  def perform(access, time)
    key = write_prevention_cache_key(access)
    ttl = calculate_ttl(time, access.access_throttling)

    # Only set the memcached lock if the ttl would be greater than 0. 0 is
    # default ttl and means forever, which we don't want. Less than zero
    # means the key would be of no use.
    #
    # Originally: https://github.com/github/github/pull/74626/files#r122095417.
    if ttl > 0
      return unless add_to_all_caches(key, time, ttl).all?
    end

    bump_not_finished = true

    begin
      access.bump!(time)
      bump_not_finished = false
    ensure
      delete_from_all_caches(key) if bump_not_finished
    end
  end

  private

  # Internal: Add a key value pair to all of the GitHub memcached clients.
  #
  # Examples
  #
  #   add_to_all_caches(
  #     "github:jobs:programmatic_access_bump:user_programmatic_access:1",
  #     Time.zone.now,
  #     1.week,
  #   )
  #   => [true, false]
  #
  # Returns an Array of Boolean results.
  def add_to_all_caches(key, value, ttl)
    caches.map { |cache| cache.add(key, value, ttl) }
  end

  # Internal: A list of all of the memcached clients we have.
  #
  # Returns an Array of GitHub::Cache::Client objects.
  def caches
    return @caches if defined?(@caches)
    @caches = [GitHub.cache, *GitHub.regional_caches.values]
  end

  # Internal: Delete a key from all of our memcached clients.
  #
  # Examples
  #
  #   delete_from_all_caches("foo")
  #   => [true, false]
  #
  # Returns an Array of Boolean results.
  def delete_from_all_caches(key)
    caches.map { |cache| cache.delete(key) }
  end

  # Internal: Calculate the "Time to live" for our memcached entries if a lock
  # on bumping is necessary.
  #
  # time       - An instance of ActiveSupport::TimeWithZone.
  # throttling - The ActiveSupport::Duration representing the time between
  #              writes.
  #
  # Returns an ActiveSupport::Duration.
  def calculate_ttl(time, throttling)
    now = Time.now.to_i
    valid_until = time.to_i + throttling

    valid_until - Time.now.to_i
  end

  # Internal: Generate the memcached key for the given access.
  #
  # access - A ProgrammaticAccess object.
  #
  # Examples
  #
  #   access = UserProgrammaticAccess.find(1)
  #   write_prevention_cache_key(access)
  #   => "github:jobs:programmatic_access_bump:8e1c09ffe40bf84374684304ce046ebd083d5f2e82fa307e0fac546f9433b2a7"
  #
  # Returns a String.
  def write_prevention_cache_key(access)
    suffix = Digest::SHA256.hexdigest("#{access.class.name.underscore}:#{access.id}")
    "#{CACHE_KEY_PREFIX}:#{suffix}"
  end
end
