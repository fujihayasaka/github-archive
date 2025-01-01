# typed: true
# frozen_string_literal: true

class IntegrationInstallation
  class UserAssociatedRepositories
    CACHE_PREFIX = "installation:user:repo_ids".freeze

    # The intention of this short TTL is to allow multiple requests to
    # rapidly paginate over a large set of repository IDs (many thousands)
    # without paying the cost of calculating associated repository IDs each
    # time, as they are unlikely to change between requests for pages.
    #
    # Change this with extreme caution.
    #
    # https://github.com/github/ecosystem-apps/issues/1541#issuecomment-871941132
    TTL = 30.seconds

    # Public: the repository IDs accessible to the given user *and*
    # installation, either returned from the GitHub.cache, or set in the cache
    # based on the value returned by the given block.
    #
    # Note: The value from the given block will be converted to JSON
    # (`#to_json`) before being stored in the cache. The inverse operation is
    # performed to return the value from the cache (E.g. `JSON.parse(value)`).
    #
    # Returns an Array of repository IDs
    def self.with_cache(user:, installation:)
      return [] unless block_given?

      return yield unless cache_enabled_for?(installation.integration)

      if cached_repo_ids = GitHub.cache.get(cache_key(user, installation))
        begin
          JSON.parse(cached_repo_ids)
        rescue JSON::ParserError
          []
        end
      else
        repo_ids = yield
        value = repo_ids.to_json

        set_cache(cache_key(user, installation), value, TTL)
        repo_ids
      end
    end

    # Public: invalidate the installation user associated repository IDs cache
    # for the given User and Installation.
    #
    # Returns nothing.
    def self.invalidate_cache(installation:, user: nil)
      return unless cache_enabled_for?(installation.integration)

      cached_user = installation.target.user? ? installation.target : user
      if cached_user.present?
        GitHub.cache.delete(cache_key(cached_user, installation))
      elsif installation.target.organization?
        # To avoid blocking requests when invalidating the cache for
        # organizations with many members, do this in a background job:
        IntegrationInstallationUserAssociatedRepositoriesCacheJob.perform_later(installation)
      end
    end

    # Internal: Is user associated repository ID caching enabled for the given
    # App?
    #
    # Returns a Boolean.
    def self.cache_enabled_for?(integration)
      return false if GitHub.enterprise?
      Flipper[:installation_user_associated_repo_ids_cache].enabled?(integration)
    end

    # Internal: The cache key for this user/installation combination.
    #
    # Accounts for different _types_ of installation (E.g. Scoped/Site etc.)
    #
    # Returns a String.
    def self.cache_key(user, installation)
      "#{CACHE_PREFIX}:#{user.id}:#{installation.class.name}:#{installation.id}"
    end

    # Internal: Set the cache.
    #
    # TODO: Remove this after the feature flag has been removed and we can test
    # expectations directly on GitHub.cache.
    #
    # Returns nothing.
    def self.set_cache(key, value, ttl)
      GitHub.cache.set(key, value, ttl)
      GitHub.regional_caches.each do |_, region_cache|
        region_cache.set(key, value, ttl)
      end
    end
  end
end
