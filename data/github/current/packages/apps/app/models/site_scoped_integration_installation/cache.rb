# typed: true
# frozen_string_literal: true

class SiteScopedIntegrationInstallation
  class Cache < InstallationCacheBase

    def initialize(namespace, parent, target, *cache_key_fragments)
      # extend the cache key with the target.
      cache_key_fragments.unshift(target.id)
      super(namespace, parent, cache_key_fragments)
    end

    def self.cache_key_prefix
      "github:api:site_scoped_installation"
    end

    def self.installation_class
      SiteScopedIntegrationInstallation
    end

    # The parent of a SiteScopedIntegrationInstallation is the Integration
    def parent_fragments
      [@parent.id, @parent.updated_at]
    end
  end
end
