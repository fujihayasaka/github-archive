# typed: true
# frozen_string_literal: true

module Apps
  class Privileged
    class ConfigurationValidator
      REQUIRED_KEYS = [
        :alias,
        :database_lookup_attributes,
        :inherits,
        :capabilities,
        :properties,
        :can_auto_install,
        :custom_instrumentation_events,
        :owners,
      ].freeze

      OPTIONAL_KEYS = [
        :available_on_ghes,
        :id, # TODO: DELETE ME BEFORE SHIPPING THIS BRANCH.
      ]

      attr_reader :config, :errors

      def initialize(config)
        @config = config
        @errors = []
      end

      def validate
        @errors << "Configuration is empty." if config.empty?
        @errors << "Configuration should have top level key 'Integration'." unless config["Integration"]
        @errors << "Configuration should have top level key 'OauthApplication'." unless config["OauthApplication"]
        unexpected_keys = (config.keys - %w[Integration OauthApplication]).map { |key| "'#{key}'" }
        @errors << "Configuration contains unexpected top level keys: #{unexpected_keys}." if unexpected_keys.any?
        return @errors if @errors.any?

        config.each do |app_type, app_configs|
          unless app_configs.is_a?(Array)
            @errors << "Configuration for '#{app_type}' should be an Array of App configurations."
            next
          end

          app_configs.each do |app_config|
            keys_without_optionals = app_config.keys - OPTIONAL_KEYS
            missing_keys = (REQUIRED_KEYS - keys_without_optionals).map { |key| "'#{key}'" }
            unexpected_keys = (keys_without_optionals - REQUIRED_KEYS).map { |key| "'#{key}'" }
            if missing_keys.any?
              missing_keys_error = missing_keys.join(", ")
              @errors << "'#{app_type}/#{app_config[:alias] || "missing alias"}' is missing the following keys: #{missing_keys_error}"
            end

            if unexpected_keys.any?
              unexpected_keys_error = unexpected_keys.join(", ")
              @errors << "'#{app_type}/#{app_config[:alias] || "missing alias"}' contains the following unexpected keys: #{unexpected_keys_error}"
            end

            unless app_config[:alias].is_a?(Symbol)
              @errors << "'#{app_type}/#{app_config[:alias]}' should have an :alias of type Symbol"
            end

            capabilities = app_config[:capabilities]
            if capabilities.is_a?(Hash)
              invalid_capability_keys = capabilities.keys.select { |key| !key.is_a?(Symbol) }.map { |key| "'#{key}'" }
              if invalid_capability_keys.any?
                invalid_capability_keys_error = invalid_capability_keys.join(", ")
                @errors << "'#{app_type}/#{app_config[:alias]}/capabilities' should all be symbols. Invalid keys: #{invalid_capability_keys_error}"
              end

              capabilities.each do |name, value|
                unless [TrueClass, FalseClass].include?(value.class) || value.respond_to?(:call)
                  @errors << "'#{app_type}/#{app_config[:alias]}/capabilities/#{name}' should be either a Boolean or a callable but was #{value.inspect}"
                end
              end
            else
              @errors << "'#{app_type}/#{app_config[:alias]}/capabilities' should be a Hash"
            end

            properties = app_config[:properties]
            if properties.is_a?(Hash)
              invalid_property_keys = properties.keys.select { |key| !key.is_a?(Symbol) }.map { |key| "'#{key}'" }
              if invalid_property_keys.any?
                invalid_property_keys_error = invalid_property_keys.join(", ")
                @errors << "'#{app_type}/#{app_config[:alias]}/properties' should all be symbols. Invalid keys: #{invalid_property_keys_error}"
              end
            else
              @errors << "'#{app_type}/#{app_config[:alias]}/properties' should be a Hash"
            end

            can_auto_install = app_config[:can_auto_install]
            unless can_auto_install.is_a?(Hash)
              @errors << "'#{app_type}/#{app_config[:alias]}/can_auto_install' should be a Hash"
            end

            owners = app_config[:owners]
            if owners.is_a?(Array)
              invalid_owners = owners.select { |owner| !owner.is_a?(String) }
              if invalid_owners.any?
                invalid_owners_error = invalid_owners.map { |o| "'#{o.inspect}' (#{o.class})" }.join(", ")
                @errors << "'#{app_type}/#{app_config[:alias]}/owners' should all be Strings. Invalid values: #{ invalid_owners_error }."
              end
            else
              @errors << "'#{app_type}/#{app_config[:alias]}/owners' should be an Array"
            end
          end
        end
        @errors
      end

      def valid?
        return @valid if defined?(@valid)
        validate
        @valid = errors.empty?
      end

      def error_message
        errors.join("\n")
      end
    end
  end
end
