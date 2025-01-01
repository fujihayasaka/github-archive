# frozen_string_literal: true
#              



module Vexi
  class FeatureFlagStorage
    StorageHash = T.type_alias { T::Hash[String, FeatureFlag] }

    attr_reader :default_enabled, :exception_feature_flags

    def initialize(storage_hash: {}, default_enabled: false, exception_feature_flags: [])
      @storage =      (storage_hash             )
      @default_enabled =      (default_enabled            )
      @exception_feature_flags =      (exception_feature_flags                  )

      configure_exception_flags
    end

    def [](key)
            (get(key, create_if_not_exists: true))
    end

    # Used by management adapter since it doesn't need to create default flags
    def get(key, create_if_not_exists:, default_enabled: @default_enabled)
      if create_if_not_exists
        @storage[key] ||= FeatureFlag.create_boolean_feature_flag(key, default_enabled)
      else
        @storage[key]
      end
    end

    # Used by vexi adapter, ensures that checking the feature flag with @default_enabled=true
    # Used by InMemoryAdapter, get_or_build ensures that checking feature flags with
    # @default_enabled=true doesn't impact tests where the feature flag is explicitly disabled.
    def get_or_build(key)
      get(key, create_if_not_exists: false) || FeatureFlag.create_boolean_feature_flag(key, @default_enabled)
    end

    def delete(key)
      @storage.delete(key)
    end

    def []=(key, value)
      @storage[key] = value
    end

    def values
      @storage.values
    end

    def reset
      @storage.clear
      configure_exception_flags
    end

    private

    # Configures exception feature flags with the inverse of the default enabled value.
    def configure_exception_flags
      # Add all the exception feature flags to @features with the inverse of the default value
      exception_feature_flags.each do |name|
        @storage[name] = FeatureFlag.create_boolean_feature_flag(name, !default_enabled)
      end
    end
  end
end
