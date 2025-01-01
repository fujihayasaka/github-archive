# typed: false
# frozen_string_literal: true

module Configurable
  module PackageAvailability
    # Key for global package availability state
    KEY           = "package_availability".freeze

    # Keys for supported package types
    # We will need to make sure this is in sync with the supported list in app\models\registry\package
    KEY_NPM       = "package_availability.npm".freeze
    KEY_RUBYGEMS  = "package_availability.rubygems".freeze
    KEY_MAVEN     = "package_availability.maven".freeze
    KEY_DOCKER    = "package_availability.docker".freeze
    KEY_NUGET     = "package_availability.nuget".freeze
    KEY_CONTAINER = "package_availability.container".freeze

    SUPPORTED_PACKAGE_TYPE_KEYS = [KEY_NPM, KEY_RUBYGEMS, KEY_MAVEN, KEY_DOCKER, KEY_NUGET, KEY_CONTAINER].freeze
    SUPPORTED_PACKAGE_TYPE_KEYS_MAP = {
      KEY_NPM => 0,
      KEY_RUBYGEMS => 1,
      KEY_MAVEN => 2,
      KEY_DOCKER => 3,
      KEY_NUGET => 5,
      KEY_CONTAINER => 6
    }
    PACKAGE_TYPE_TO_NAME = {
      0 => "npm",
      1 => "rubygems",
      2 => "maven",
      3 => "docker",
      5 => "nuget",
      6 => "container"
    }

    # values for global package availability
    ENABLED = "enabled".freeze    # all package types are enabled
    MANAGED = "managed".freeze    # package types are managed
    DISABLED = "disabled".freeze  # all package types are disabled

    PACKAGE_AVAILABILITY_VALUES = [ENABLED, MANAGED, DISABLED].freeze

    # values for individual package type
    TYPE_ENABLED = "enabled".freeze    # package type enabled
    TYPE_DISABLED = "disabled".freeze  # package type disabled

    PACKAGE_TYPE_STATUS_VALUES = [TYPE_ENABLED, TYPE_DISABLED].freeze

    # Gets the global package availability state
    #
    # Returns: enabled, managed or disabled
    def self.package_availability
      global_status = Configuration::Entry.named(KEY).first

      if !global_status.nil?
        return global_status.value
      end

      ENABLED
    end

    # Sets the global package availability state
    def set_package_availability(value, actor:)
      config.set(KEY, value, actor)
    end

    # Sets package availability state for given package_type
    def set_package_type_availability(package_type_name, enabled, actor:)
      config.set(to_package_key(package_type_name), enabled ? TYPE_ENABLED : TYPE_DISABLED, actor)
    end

    # Checks if the given package_type would be enabled if global package availability was managed mode.
    # Note the result is not affected by the global settings. It will return true if the configuration is missing or
    # is enabled for the given package type even if global setting is disabled
    def managed_package_type_enabled?(package_type_name)
      !package_type_disabled?(to_package_key(package_type_name))
    end

    # Get all supported package types that are enabled
    # Returns: array of package type values
    def enabled_package_types(map_to_names: false)
      disabled_package_types = []

      SUPPORTED_PACKAGE_TYPE_KEYS.each do |package_type_key|
        if package_type_disabled?(package_type_key)
          disabled_package_types.push(SUPPORTED_PACKAGE_TYPE_KEYS_MAP[package_type_key])
        end
      end

      package_types = SUPPORTED_PACKAGE_TYPE_KEYS_MAP.values - disabled_package_types
      return package_types unless map_to_names

      package_types.map { |package_type| PACKAGE_TYPE_TO_NAME[package_type] }
    end

    private

    # Converts the given package name to corresponding KEY in the storage
    def to_package_key(package_type_name)
      KEY + "." + package_type_name.to_s.downcase
    end

    def package_type_disabled?(package_type_key)
      config.get(package_type_key) == TYPE_DISABLED
    end
  end
end
