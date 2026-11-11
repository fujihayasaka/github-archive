# typed: true
# frozen_string_literal: true

class InstallationCacheBase
  def initialize(namespace, parent, *cache_key_fragments)
    @cache_key_fragments = cache_key_fragments
    @namespace = namespace
    @parent = parent
  end

  # Internal: To be implemented by a subclass
  #
  # Returns a String
  def self.cache_key_prefix
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  # Internal: To be implemented by a subclass
  #
  # Returns the [Site]ScopedIntegrationInstallation class
  def self.installation_class
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  # Internal: To be implemented by a subclass
  #
  # Returns extra cache key fragments derived from the parent object
  def parent_fragments
    raise NotImplementedError, "needs to be implemented by subclass"
  end

  # Public: Find a [Site]ScopedIntegrationInstallation record based on the parent's
  # primary ID and the generated cache key.
  #
  # Returns a [Site]ScopedIntegrationInstallation or nil.
  def get
    cached_id = GitHub.cache.get(cache_key)
    return unless cached_id

    installation_class.find_by(id: cached_id)
  end

  # Internal: Generate a cache key based on parent's primary ID joined with
  # the provided cache key fragments.
  #
  # Example
  #
  #   cache_key
  #   # => 'github:api:scoped_installation:nHoicqWoNt63sW+Ur3F6xpULtId5c7IvkO7H7W4eeE8='
  #
  # Returns a String.
  def cache_key
    return @cache_key if defined?(@cache_key)

    cache_key_suffix = @cache_key_fragments.unshift(*parent_fragments).map(&:to_s).join(":")
    @cache_key = "#{self.class.cache_key_prefix}:#{Digest::SHA256.base64digest(cache_key_suffix)}"
  end

  # Public: Determine if the key exists in memcached.
  #
  # Returns Boolean.
  def exist?
    cached_id = GitHub.cache.get(cache_key)

    @stats_result = cached_id ? "result:hit" : "result:miss"
    GitHub.dogstats.increment("api.integrations.access_tokens.create.#{@namespace}.cache", tags: [@stats_result])

    return false unless cached_id

    if installation_class.exists?(cached_id)
      @valid_cache_hit = true
      return true
    end

    # The cached id points to a record that no longer exists. Drop the stale
    # entry so subsequent requests don't keep paying for the slow lookup until
    # the TTL expires; this matters most when the cache key is shared across
    # many semantically equivalent requests.
    GitHub.dogstats.increment("api.integrations.access_tokens.create.#{@namespace}.cache.record_missing")
    delete_cache
    false
  end

  # Public: Write a successful [Site]ScopedIntegrationInstallation::*Creator::Result
  # to memcache for later use.
  #
  # result - An instance of [Site]ScopedIntegrationInstallation::*Creator::Result
  #
  # Returns the given argument.
  def set(result)
    return result unless result.success?
    return result if @valid_cache_hit

    write_cache(result.installation.id, 1.day)
    result
  end

  private

  def write_cache(value, ttl)
    GitHub.cache.set(cache_key, value, ttl)
    GitHub.regional_caches.each do |_, region_cache|
      region_cache.set(cache_key, value, ttl)
    end
  end

  def delete_cache
    GitHub.cache.delete(cache_key)
    GitHub.regional_caches.each do |_, region_cache|
      region_cache.delete(cache_key)
    end
  end

  def installation_class
    self.class.installation_class
  end
end
