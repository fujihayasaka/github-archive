# typed: true
# frozen_string_literal: true

# Internal: A thread-local, in memory cache and Rack middleware for permission data
#
# This cache is cleared when Ability data is granted, revoked, or cleared.
# See the Ability model for where that happens and also for where this cache is used.
class PermissionCache
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
    return yield if !enabled?

    result = get_with_presence(key)
    return result unless result.is_a?(Symbol) && result == :cache_miss

    data[key] = yield
  end

  def self.set(key, value)
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

  def self.enabled?
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
