# typed: true
# frozen_string_literal: true

# Management and storage of configuration for internal GitHub and OAuth Apps.
module Apps
  class Privileged
    class Registry
      NIL_ID = ->(*) { nil }
      VALID_APP_TYPES = %w(Integration OauthApplication)

      include Singleton

      class InvalidConfigurationError < ArgumentError; end

      # Public: add/modify a configuration entry in the internal Apps
      # registry.
      #
      # app                      - Integration/OauthApplication (optional): The App
      #                            that is being configured. Either supply the `app` OR
      #                            `type` argument.
      # type                     - String (optional): One of "Integration" or
      #                            "OauthApplication". Allows the "global" configuration
      #                            to be modified without passing an `app`.
      # app_alias                - Symbol (required): The alias to identify the
      #                            configuration entry. Note: the configuration entry
      #                            associated with this alias will be updated in the
      #                            case that `type` is supplied OR the `app` cannot be
      #                            found in the configuration. This allows a
      #                            configuration entry to be updated so that an alias
      #                            points to a different App.
      # id                       - Proc (optional): A callable that should return the
      #                            database ID of the configured App. The Proc may
      #                            return `nil`. If not supplied, a default Proc that
      #                            returns `nil` will be used.
      # inherits                 - Array (optional): A list of symbols that
      #                            reference other non-app specific
      #                            configurations in the internal registry.
      #                            Capabilities will be inherited from these
      #                            configurations.
      # capabilities             - Hash (optional): The internal capabilities granted
      #                            to this App. See Apps::Privileged::CONFIGURATION for
      #                            examples.
      # properties               - Hash (optional): The properties of this App.  See
      #                            Apps::Privileged::CONFIGURATION for examples.
      # can_auto_install         - Hash (optional): A mapping of
      #                            AutomaticAppInstallation::TRIGGER_HANDLERS to
      #                            callables.
      # custom_instrumentation_events - Hash (optional): A mapping of actions to overrides
      #                            for the audit log event, which can either be a
      #                            string for the audit log instrumentation key or
      #                            a proc
      #
      # Returns a Hash: The modifed configuration of the Registry.
      def self.configure(app: nil, type: nil, app_alias:, id: NIL_ID, inherits: [], capabilities: {}, properties: {}, can_auto_install: {}, custom_instrumentation_events: {}, owners: [])
        instance.configure(
          app: app,
          type: type,
          app_alias: app_alias,
          id: id,
          inherits: inherits,
          capabilities: capabilities,
          properties: properties,
          can_auto_install: can_auto_install,
          custom_instrumentation_events: custom_instrumentation_events,
          owners: [],
        )
      end

      # Public: the current configuration.
      #
      # Note: Always returns Apps::Privileged::CONFIGURATION in Production.
      #
      # Returns a Hash: The current configuration of the Registry.
      def self.configuration
        instance.configuration
      end

      # Public: reset the configuration back to its original state.
      #
      # Note: The original configuration of the Registry will always be as it
      # appears in Production.
      #
      # Returns a Hash: The original configuration of the Registry.
      def self.reset_configuration!
        instance.reset_configuration!
      end

      # Public: Find an App's configuration.
      #
      # alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # id    - Integer: The database ID of the Integration or OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns a configuration Hash for the App or empty Hash if the App has
      # not been configured.
      def self.find_configuration(app_alias: nil, id: nil, type:)
        instance.find_configuration(app_alias: app_alias, id: id, type: type)
      end

      # Public: All App aliases configured, regardless of type. Does not
      # include the default (global or internal) aliases.
      #
      # Returns an Array of Symbols.
      def self.all_aliases
        instance.configuration.flat_map do |_, configs|
          configs.reject do |config|
            config[:alias] == :global || config[:alias] == :internal
          end.map { |c| c[:alias] }
        end.uniq
      end

      def self.all_configured_ids_of_type(type)
        instance.all_configured_ids_of_type(type)
      end

      # Public: The ID of a given app with alias/type fetched from the
      # internal registry's cache, which is built once when the configuration
      # is first validated.
      #
      # app_alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns an Integer or nil if the alias/type is not found in the cache.
      def self.app_id(app_alias:, type:)
        instance.app_id(app_alias: app_alias, type: type)
      end

      # Public: the number of configured internal Apps.
      #
      # type  - String (optional). Either "Integration" or "OauthApplication".
      #         When not supplied returns the count of both types of App.
      #
      # Returns an Integer.
      def self.count_apps(type: nil)
        configs =
          case type
          when "Integration"; instance.configuration["Integration"]
          when "OauthApplication"; instance.configuration["OauthApplication"]
          else; instance.configuration["Integration"] + instance.configuration["OauthApplication"]
          end

        configs.reduce(0) do |total, app|
          total += 1 unless app[:alias] == :global || app[:alias] == :internal
          total
        end
      end

      # Internal: Add or modify a configuration entry in the Registry.
      #
      # Note: Don't call this method directly. See Apps::Privileged.configure for
      # the public documentation.
      #
      # Returns a Hash: The modified configuration of the Registry.
      def configure(app: nil, type: nil, app_alias:, id: NIL_ID, inherits: [], capabilities: {}, properties: {}, can_auto_install: {}, custom_instrumentation_events: {}, owners: [])
        return configuration unless registry_configurable?

        raise ArgumentError.new("Supply `app` or `type` keyword") unless app || %w(Integration OauthApplication).include?(type)

        type = app.present? ? app.class.name : type
        config = nil

        config = defined?(@configuration) ? @configuration : default_configuration

        index = nil
        if app.nil?
          index = config[type].find_index { |a| a[:alias] == app_alias }
        else
          index = config[type].find_index { |a| a[:id].call == app.id || a[:alias] == app_alias }
        end

        app_config = {
          alias: app_alias,
          id: id,
          inherits: inherits,
          capabilities: capabilities,
          properties: properties,
          can_auto_install: can_auto_install,
          custom_instrumentation_events: custom_instrumentation_events,
          owners: owners,
        }

        if index.nil? # App was never previously configured, append it to the config
          config[type].push(app_config)
        else
          # App's config is being updated. Preserve its position in the list of
          # apps so that our caches don't have to be recomputed.
          config[type].delete_at(index)
          config[type].insert(index, app_config)
        end

        validator = Apps::Privileged::ConfigurationValidator.new(config)
        raise InvalidConfigurationError.new(validator.error_message) unless validator.valid?

        # TODO: Load the :global config for all VALID_APP_TYPES here to account
        # for tests that configure a fixture app of one type but then depend on
        # the default for a non-configured app of the other type.
        inherited_configs = ([:global] + app_config[:inherits]).map do |inherited_alias|
          config[type].find { |cfg| cfg[:alias] == inherited_alias }
        end.compact

        (inherited_configs + [app_config]).each do |cfg|
          preload_app_id(cfg, type, config[type].index(cfg))
        end

        @configuration = config
      end

      def configuration
        return @configuration if defined?(@configuration)

        @configuration = validate_configuration!(default_configuration)
      end

      def reset_configuration!
        return unless registry_configurable?
        @configuration = validate_configuration!(default_configuration)
      end

      def reload_caches!
        config = defined?(@configuration) ? @configuration : default_configuration
        self.preload_app_ids(config)
      end

      # Privileged: Find an App's configuration.
      #
      # alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # id    - Integer: The database ID of the Integration or OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns a configuration Hash for the App or empty Hash if the App has
      # not been configured.
      def find_configuration(app_alias: nil, id: nil, type:)
        empty_config = {}
        return empty_config unless id || app_alias

        unless VALID_APP_TYPES.include?(type)
          raise ArgumentError.new("supply a valid `type` argument. One of: #{VALID_APP_TYPES}")
        end

        # This check pre-loads the configuration the first time this method is called.
        return empty_config if configuration.empty?

        index =
          if app_alias.present?
            index_of_alias(app_alias, type)
          elsif id.present?
            index_of_id(id, type)
          end

        index && configuration.fetch(type)[index] || empty_config
      end

      # Privileged: the IDs of all internal Apps that have been configured.
      #
      # type  - String. One of "Integration" or "OauthApplication"
      #
      # Returns an Array of Integers.
      def all_configured_ids_of_type(type)
        configuration
        @index_of_configurations_by_app_id.select { |k, _| /#{type}:/.match(k) }.map { |k, _| k.split(":").last }
      end

      # Internal: The ID of a given app with alias/type fetched from the
      # internal registry's cache, which is built once when the configuration
      # is first validated.
      #
      # app_alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns an Integer or nil if the alias/type is not found in the cache.
      def app_id(app_alias:, type:)
        cfg = find_configuration(app_alias: app_alias, type: type)
        return nil if cfg[:id].nil? # No chance of finding a cached ID if app has not been configured in the registry.

        cached_app_id(app_alias: app_alias, type: type)
      end

      private

      # Private: preloads all App IDs based on their configured callables and
      # creates indexes that are used to efficiently lookup a configured App
      # based on either its ID or alias.
      #
      # config  - Hash. A valid Apps::Privileged configuration.
      #
      # Returns a Hash: the unmodified config.
      def preload_app_ids(config)
        start_time = Time.now
        initialize_caches!

        ActiveRecord::Base.connected_to(role: :reading) do
          VALID_APP_TYPES.each do |type|
            config[type].each_with_index do |config, index|
              preload_app_id(config, type, index)
            end
          end
        end

        duration_in_ms = (Time.now - start_time) * 1_000
        GitHub.dogstats.distribution("apps_internal.registry.preload_app_ids.distribution", duration_in_ms)
        GitHub.dogstats.gauge("apps_internal.registry.configured_apps.count", @index_of_configurations_by_app_id.size)

        config
      end

      # Private: preloads a single app ID based on its configured callable ID
      # finder and populates indexes that are used to efficiently lookup the
      # configured app based on either its ID or alias.
      #
      # app_config  - Hash. A valid Apps::Privileged configuration for a single app.
      # type        - String: The class of the App: One of 'Integration' or
      #               'OauthApplication'
      # index       - Integer. The position of the app's settings in the
      #             configuration.
      #
      # Returns a Hash: the unmodified app config.
      def preload_app_id(app_config, type, index)
        ensure_caches_initialized!

        @index_of_configurations_by_alias["#{type}:#{app_config[:alias]}"] = index

        app_id = app_config[:id].call
        if app_id
          @cache_of_id_by_alias["#{type}:#{app_config[:alias]}"] = app_id
          @index_of_configurations_by_app_id["#{type}:#{app_id}"] = index
        end
        app_config
      end

      # Private: ensures that the instance variables used to index app IDs and
      # their configuration locations are initialized only when required.
      def ensure_caches_initialized!
        initialize_caches! unless defined?(@index_of_configurations_by_alias) &&
          defined?(@index_of_configurations_by_app_id) && defined?(@cache_of_id_by_alias)
      end

      def cached_app_id(app_alias:, type:)
        @cache_of_id_by_alias["#{type}:#{app_alias}"]
      end

      def initialize_caches!
        @cache_of_id_by_alias = {}
        @index_of_configurations_by_alias = {}
        @index_of_configurations_by_app_id = {}
      end

      # Private: A safely modifiable copy of the default configuration values.
      #
      # Returns a Hash.
      def default_configuration
        # Use Rails' Object#deep_dup method instead of Marshal.dump here
        # because the configuration contains Procs, which can't be serialized
        # by Marshal.
        Apps::Privileged.default_configuration.deep_dup
      end

      def registry_configurable?
        Rails.env.test? || Rails.env.development?
      end

      def validate_configuration!(config)
        validator = Apps::Privileged::ConfigurationValidator.new(config)
        raise InvalidConfigurationError.new(validator.error_message) unless validator.valid?
        config = preload_app_ids(config)

        config
      end

      def index_of_alias(app_alias, type)
        return nil unless @index_of_configurations_by_alias
        @index_of_configurations_by_alias["#{type}:#{app_alias}"]
      end

      def index_of_id(id, type)
        return nil unless @index_of_configurations_by_app_id
        @index_of_configurations_by_app_id["#{type}:#{id}"]
      end
    end
  end
end
