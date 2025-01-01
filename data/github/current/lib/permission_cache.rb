# typed: true
# frozen_string_literal: true

require "scientist"

# Internal: A thread-local, in memory cache and Rack middleware for permission data
#
# This cache is cleared when Ability data is granted, revoked, or cleared.
# See the Ability model for where that happens and also for where this cache is used.
class PermissionCache
  include Scientist
  extend Scientist

  def initialize(app)
    @app = app
  end

  def call(env)
    PermissionCache.enable { @app.call(env) }
  end

  def self.clear
    data.clear
  end

  # Public: fetch is the preferred external interface for obtaining data from the cache.
  #
  # fetch will return a value from the cache if it exists,
  # and execute the block, and then cache and return the result if the key is not present.
  #
  # the key should be array, with the first value being the "namespace" of the query
  # and the rest of the array being data specific to the request.
  # Example: ["most_capable_abilties_between", User, 1, Repository, 4]
  def self.fetch(key, &block)
    if gitauth_cache_experiment_enabled?
      return fetch_experiment(key, &block)
    end
    return yield if !enabled?

    result = get_with_presence(key)
    return result unless result.is_a?(Symbol) && result == :cache_miss

    data[key] = yield
  end

  # validate that the cached value matches the computed value
  # calculate the frequency of cache hits vs misses
  # does not return a value, but caches the result for future comparison
  def self.fetch_experiment(key, &block)
    result = science "permissioncache_fetch_gitauth_experiment" do |e|
      e.use do
        yield if block_given?
      end
      e.try do
        cache_result = data.fetch(key, :cache_miss)
        cache_status = (cache_result.is_a?(Symbol) && cache_result == :cache_miss) ? "miss" : "hit"
        GitHub.dogstats.increment("permission_cache.gitauth.fetch", tags: ["result:#{cache_status}", "namespace:#{namespace(key)}"])
        cache_result
      end
      e.ignore { |control, candidate| control.nil? || candidate == :cache_miss }
    end

    data[key] = result if block_given?
  end
  private_class_method :fetch_experiment

  def self.set(key, value)
    if gitauth_cache_experiment_enabled?
      data[key] = value
    end

    return if !enabled?
    data[key] = value
  end

  # Public: get can be used to check for and return a value from the cache without setting a value
  # if the key is not present in the cache. This is useful for bulk loaders where the fetching
  # from the cache is decoupled from the database query.
  #
  # If the key is missing from the cache, nil is returned. If PermissionCache is not enabled
  # nil is returned. Callsites should implement checks for both to avoid confusion about these
  # conditions, and a "no abilities" result which could also be nil.
  #
  # the key should be an array, with the first value being the "namespace" of the query
  # and the rest of the array being data specific to the request.
  # Example: ["most_capable_abilties_between", User, 1, Repository, 4]
  def self.get(key)
    if gitauth_cache_experiment_enabled?
      result = data.fetch(key, :cache_miss)
      cache_status = (result.is_a?(Symbol) && result == :cache_miss) ? "miss" : "hit"
      GitHub.dogstats.increment("permission_cache.gitauth.get", tags: ["result:#{cache_status}", "namespace:#{namespace(key)}"])
    end

    return nil if !enabled?
    result = get_with_presence(key)
    return nil if result.is_a?(Symbol) && result == :cache_miss
    result
  end

  # Private: get_with_presence can be used to check for and return a value from the cache without setting a value
  # if the key is not present in the cache. It differs from get in that it returns a signal to the caller
  # if the cache is not enabled or if they key is missing from the cache
  #
  # If the key is missing from the cache, :cache_miss is returned. If PermissionCache is not enabled
  # :cache_miss is returned.
  #
  # the key should be an array, with the first value being the "namespace" of the query
  # and the rest of the array being data specific to the request.
  # Example: ["most_capable_abilties_between", User, 1, Repository, 4]
  def self.get_with_presence(key)
    return :cache_miss if !enabled?
    result = data.fetch(key, :cache_miss)
    cache_status = (result.is_a?(Symbol) && result == :cache_miss) ? "miss" : "hit"
    GitHub.dogstats.increment("ability.cache", tags: ["result:#{cache_status}", "namespace:#{namespace(key)}"])
    result
  end
  private_class_method :get_with_presence

  def self.key?(key)
    return if !enabled?
    data.key?(key)
  end

  def self.enable(&block)
    clear
    self.enabled = true
    yield
  ensure
    self.enabled = false
    clear
  end

  def self.data
    Thread.current[:ability_cache_data] ||= {}
  end
  private_class_method :data

  def self.gitauth_cache_experiment_enabled?
    return false unless GitHub.gitauth_host?
    return false unless Thread.current[:ability_cache_enabled]
    GitHub.flipper[:gitauth_permission_cache_experiment].enabled?
  end

  def self.gitauth_cache_enabled?
    return false unless GitHub.gitauth_host?
    return false if gitauth_cache_experiment_enabled?
    GitHub.flipper[:gitauth_permission_cache].enabled?
  end

  def self.enabled?
    return false if GitHub.gitauth_host? && !gitauth_cache_enabled?
    Thread.current[:ability_cache_enabled] || false
  end

  def self.enabled=(flag)
    Thread.current[:ability_cache_enabled] = flag
  end
  private_class_method :enabled=

  def self.any?
    data.any?
  end

  def self.each(&blk)
    data.each(&blk)
  end

  def self.namespace(key)
    return "unknown" unless key.instance_of?(Array) && key.first.instance_of?(String)
    key.first
  end
end
