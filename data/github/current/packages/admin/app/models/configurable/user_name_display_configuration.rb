# typed: true
# frozen_string_literal: true

module Configurable
  module UserNameDisplayConfiguration
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "user_name_display".freeze
    UPDATE_INSTRUMENTATION_KEY = "update_user_name_display".freeze

    HANDLE = "handle".freeze  # Only show GitHub handle
    NAME_AND_HANDLE = "name_handle".freeze # Show profile name and handle
    CONFIG_VALUES = [HANDLE, NAME_AND_HANDLE].freeze

    ENTERPRISE_OWNER_REQUIRED_ERROR = "User name display configuration can only be set by enterprise owner."
    ORGANIZATION_ADMIN_REQUIRED_ERROR = "User name display configuration can only be set by organization owner."
    UNSUPPORTED_CONFIG_VALUE = "You provided an invalid config value. Please try again."
    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support user name display configuration."

    class UserNameDisplayConfigurationError < StandardError; end

    # Public: Set user name display configuration on the object.
    #
    # Returns nothing.
    def update_user_name_display_configuration(actor: nil, config_value: nil, final: false)
      unless eligible_for_user_name_display_configuration?
        raise UserNameDisplayConfigurationError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      if self.is_a?(Organization)
        unless self.adminable_by?(actor)
          raise UserNameDisplayConfigurationError.new ORGANIZATION_ADMIN_REQUIRED_ERROR
        end
      elsif self.is_a?(Business)
        unless self.owner?(actor)
          raise UserNameDisplayConfigurationError.new ENTERPRISE_OWNER_REQUIRED_ERROR
        end
      end

      unless CONFIG_VALUES.include?(config_value)
        raise UserNameDisplayConfigurationError.new UNSUPPORTED_CONFIG_VALUE
      end

      previous_value = config.get(KEY)
      return unless config.set!(KEY, config_value, actor, final)

      instrument_user_name_display_configuration(previous_value: previous_value, config_value: config_value, actor: actor)
    end

    # Public: Resets the display name configuration to unset.
    #
    # actor - The User performing the reset
    #
    # Returns nothing.
    def reset_user_name_display_configuration(actor: nil)
      previous_value = config.get(KEY)
      return unless config.delete(KEY)

      instrument_user_name_display_configuration(previous_value: previous_value, config_value: nil, actor: actor)
    end

    # Public: Display name configuration value
    #
    # Returns String
    def user_name_display_configuration_value
      config.get(KEY) || default_user_name_display_configuration_value
    end
    async_configurable :user_name_display_configuration_value

    # Public: Async display name configuration value with defaulting.
    #
    # This method overrides the one defined by `async_configurable` above.
    # The `async_configurable` call is still necessary to populate `async_configurable_methods`,
    # but this override is required to ensure proper defaulting when the configuration value is nil.
    #
    # Returns Promise<String>
    def async_user_name_display_configuration_value
      ::Platform::Loaders::Configuration.load(self, :user_name_display_configuration_value).then do |value|
        value || default_user_name_display_configuration_value
      end
    end

    # Public: Display name configuration value is set locally
    #
    # Returns String
    def user_name_display_configuration_local?
      config.local?(KEY)
    end

    # Public: Display name configuration value is set by policy
    #
    # Returns String
    def user_name_display_configuration_policy?
      config.inherited?(KEY)
    end

    # Public: Display name configuration value is set by policy for all children
    #
    # Returns String
    def user_name_display_configuration_final?
      config.final?(KEY) || false
    end

    # Public: Is user display name configuration set to handle (default)
    #
    # Returns Boolean.
    def handle_user_display_name_configuration?
      user_name_display_configuration_value == HANDLE
    end

    # Public: Is user display name configuration set to name and handle
    #
    # Returns Boolean.
    def name_and_handle_user_display_name_configuration?
      user_name_display_configuration_value == NAME_AND_HANDLE
    end

    # Public: Is the feature enabled for the business?
    #
    # Returns Boolean.
    def eligible_for_user_name_display_configuration?
      return self.business&.eligible_for_user_name_display_configuration? if self.is_a?(Organization)
      return false unless self.is_a?(Business)

      true
    end

    # Private: Instrument user name display configuration update event.
    #
    # Returns nothing.
    def instrument_user_name_display_configuration(previous_value:, config_value:, actor:)
      payload = {
        actor: actor,
        previous_value: previous_value,
        configuration_value: config_value
      }

      case self
      when ::Organization
        payload[:org] = self
        payload[:business] = self.business if self.business
      when ::Business
        payload[:business] = self
      end

      # Hydro event
      GlobalInstrumenter.instrument(UPDATE_INSTRUMENTATION_KEY, payload)
    end

    private

    def default_user_name_display_configuration_value
      return NAME_AND_HANDLE if default_to_name_and_handle?

      HANDLE
    end

    def default_to_name_and_handle?
      return true if GitHub.enterprise?

      case self
      when ::Organization
        business&.enterprise_managed_user_enabled? || false
      when ::Business
        enterprise_managed_user_enabled?
      else
        false
      end
    end
  end
end
