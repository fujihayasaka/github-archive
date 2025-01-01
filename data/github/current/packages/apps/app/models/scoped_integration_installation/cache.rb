# typed: true
# frozen_string_literal: true

class ScopedIntegrationInstallation
  class Cache < InstallationCacheBase
    def self.cache_key_prefix
      "github:api:scoped_installation"
    end

    def self.installation_class
      ScopedIntegrationInstallation
    end

    def parent_fragments
      [@parent.id, @parent.integration_version_number, @parent.updated_at]
    end
  end
end
