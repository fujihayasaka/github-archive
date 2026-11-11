# typed: strict
# frozen_string_literal: true

module SettingsCoreV2
  # Cache for holding the results from setting providers
  class SettingsCache
    sig { void }
    def initialize
      @entries = T.let({}, T::Hash[String, T.nilable(ISetting)])
    end

    # Returns the cached setting for the given key, or :miss if not cached.
    sig { params(provider_name: String, setting_name: String, resource: T.untyped).returns(T.any(T.nilable(ISetting), Symbol)) }
    def get(provider_name, setting_name, resource)
      key = cache_key(provider_name, setting_name, resource)
      @entries.key?(key) ? @entries[key] : :miss
    end

    # Stores a setting (or nil for empty result) in the cache.
    sig { params(provider_name: String, setting_name: String, resource: T.untyped, setting: T.nilable(ISetting)).void }
    def put(provider_name, setting_name, resource, setting)
      key = cache_key(provider_name, setting_name, resource)
      @entries[key] = setting
    end

    # Clears all entries for a given provider.
    sig { params(provider_name: String, setting_name: T.nilable(String)).void }
    def clear_provider(provider_name, setting_name: nil)
      prefix = "#{provider_name}/"
      prefix += "#{setting_name}/" if setting_name
      @entries.delete_if { |key, _| key.start_with?(prefix) }
    end

    private

    sig { params(provider_name: String, setting_name: String, resource: T.untyped).returns(String) }
    def cache_key(provider_name, setting_name, resource)
      record = resource.respond_to?(:internal_record) ? resource.internal_record : resource
      "#{provider_name}/#{setting_name}/#{record.class.name}/#{record.id}"
    end
  end
end
