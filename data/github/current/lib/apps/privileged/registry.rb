# typed: true
# frozen_string_literal: true

# Management and storage of configuration for internal GitHub and OAuth Apps.
module Apps
  class Privileged
    class Registry
      include Scientist

      NIL_ID = ->(*_) { nil }
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
      # database_lookup_attributes  - Hash (optional): a set of model attributes used
      #                               efficiently lookup the ID of the
      #                               configured app. Valid attributes for
      #                               lookup are: `{owner,user}_id`, `name`,
      #                               `slug`, `key`, `id`.
      #                               If not supplied, a default attribute that
      #                               returns and ID of `nil` will be used.
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
      # available_on_ghes         - Boolean (optional): Whether this app should
      #                             be loaded into the registry when GitHub.enterprise?
      #
      # Returns a Hash: The modifed configuration of the Registry.
      def self.configure(app: nil, type: nil, app_alias:, id: NIL_ID, database_lookup_attributes: { id: nil }, inherits: [], capabilities: {}, properties: {}, can_auto_install: {}, custom_instrumentation_events: {}, owners: [], available_on_ghes: true)
        instance.configure(
          app: app,
          type: type,
          app_alias: app_alias,
          id: id,
          database_lookup_attributes: database_lookup_attributes,
          inherits: inherits,
          capabilities: capabilities,
          properties: properties,
          can_auto_install: can_auto_install,
          custom_instrumentation_events: custom_instrumentation_events,
          owners: [],
          available_on_ghes: available_on_ghes,
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

      # Public: The Integration or OauthApplication object of a given app with
      # alias/type fetched from the internal registry's cache, which is built
      # once when the configuration is first validated.
      #
      # app_alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns an Integration, OauthApplication or nil if the alias/type is
      # not found in the cache.
      def self.app(app_alias:, type:)
        instance.app(app_alias: app_alias, type: type)
      end

      # Public: Look up an app's ID directly from the database using its configured
      # database lookup attributes, bypassing the cache.
      #
      # app_alias - Symbol: The configured alias of the Integration or OauthApplication
      # type      - String: The class name of the App: One of 'Integration' or 'OauthApplication'
      #
      # Returns an Integer (the app ID) or nil if the app can't be found in the database.
      def self.app_id_from_database(app_alias:, type:)
        config = instance.find_configuration(app_alias: app_alias, type: type)
        instance.app_id_from_database(config[:database_lookup_attributes], type)
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
      def configure(app: nil, type: nil, app_alias:, id: NIL_ID, database_lookup_attributes: { id: nil }, inherits: [], capabilities: {}, properties: {}, can_auto_install: {}, custom_instrumentation_events: {}, owners: [], available_on_ghes: true)
        return configuration unless registry_configurable?

        raise ArgumentError.new("Supply `app` or `type` keyword") unless app || %w(Integration OauthApplication).include?(type)

        type = app.present? ? app.class.name : type
        config = nil

        config = defined?(@configuration) ? @configuration : default_configuration

        index = nil
        if app.nil?
          index = config[type].find_index { |a| a[:alias] == app_alias }
        else
          index = config[type].find_index do |a|
            config_id = app_id_for_db_attrs(a[:database_lookup_attributes], type)
            config_id == app.id || a[:alias] == app_alias
          end
        end

        app_config = {
          alias: app_alias,
          id: id,
          database_lookup_attributes: database_lookup_attributes,
          inherits: inherits,
          capabilities: capabilities,
          properties: properties,
          can_auto_install: can_auto_install,
          custom_instrumentation_events: custom_instrumentation_events,
          owners: owners,
          available_on_ghes: available_on_ghes,
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

      # Internal: Reloads all configured app IDs from the database and rebuilds
      # the in-memory cache to make sure apps can be found via their alias and
      # that capability checks work correctly.
      #
      # NOTE: This method is only here to support bootstrapping of
      # environments, E.g. in tests or when seeding the database. It should be
      # unnecessary to call this in production.
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
        cached_app_id(app_alias: app_alias, type: type)
      end

      # TODO: Currently only used by
      # Apps::Privileged.all_apps_with_capabilities. We should push this
      # memoized version as far into the privileged apps system as possible
      # (E.g. Apps::Privileged.integration etc.) to save a lot of DB lookups.
      #
      # TODO: We should also consider populating this cache during the
      # preload_app_ids phase. We're looking up the apps anyway and building
      # caches, so it makes sense.
      #
      # Internal: The Integration or OauthApplication object of a given app with
      # alias/type fetched from the internal registry's cache, which is built
      # once when the configuration is first validated.
      #
      # app_alias - Symbol: The configured alias of the Integration or
      #         OauthApplication
      # type  - String: The class of the App: One of 'Integration' or
      #         'OauthApplication'
      #
      # Returns an Integration, OauthApplication or nil if the alias/type is
      # not found in the cache.
      def app(app_alias:, type:)
        id = app_id(app_alias: app_alias, type: type)
        return if id.blank?

        cached_app = @cache_of_app_by_id["#{type}:#{id}"]
        return cached_app if cached_app.present?

        klass = Object.const_get(type)
        app = klass.find_by(id: id)
        return if app.blank?

        @cache_of_app_by_id["#{type}:#{id}"] = app
        app
      end

      # Public: Look up an app's ID directly from the database using database lookup attributes,
      # bypassing the cache.
      #
      # db_lookup_attrs - Hash: A set of model attributes used to find the app in the database
      # type            - String: The class name of the App: One of 'Integration' or 'OauthApplication'
      #
      # Returns an Integer (the app ID) or nil if the app can't be found in the database.
      def app_id_from_database(db_lookup_attrs, type)
        app_id_for_db_attrs(db_lookup_attrs, type)
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
        indexes = batched_preload_app_ids(config)

        @index_of_configurations_by_app_id  = indexes[:index_of_configurations_by_app_id]
        @index_of_configurations_by_alias   = indexes[:index_of_configurations_by_alias]
        @cache_of_id_by_alias               = indexes[:cache_of_id_by_alias]

        duration_in_ms = (Time.now - start_time) * 1_000
        GitHub.dogstats.distribution("apps_internal.registry.preload_app_ids.distribution", duration_in_ms)
        GitHub.dogstats.gauge("apps_internal.registry.configured_apps.count", @index_of_configurations_by_app_id.size)

        config
      end

      # Collects app configurations and, using a new
      # `database_lookup_attributes` key, tries to make as few SQL queries as
      # possible to lookup all of the configured App ids.
      #
      # The main strategy involves grouping app configurations by a common
      # owner (or User) ID, selecting all apps belonging to that owner in one
      # query and then matching the selected app database IDs to their
      # respective configurations and building the indexes.
      #
      # This becomes more effective the more privileged apps define either an
      # owner_id (Integration) or user_id (OauthApplication) attribute. As this
      # tends to be a fairly stable value, it's expected to be relatively easy
      # to migrate those apps that don't currently specify this information.
      #
      # Returns a Hash of indexed App config/ID information.
      def batched_preload_app_ids(config)
        indexes = {
          index_of_configurations_by_alias: {},
          index_of_configurations_by_app_id: {},
          cache_of_id_by_alias: {}
        }

        VALID_APP_TYPES.each do |app_type|
          owner_field =
            case app_type
            when "Integration"; :owner_id
            when "OauthApplication"; :user_id
            end

          database_lookup_attributes_grouped_by_owner(config[app_type], owner_field).each do |owner_id, db_attrs_for_apps|
            owner_id = owner_id_or_special_owner_id(owner_id)

            # The list of possible database attributes that we can use in a
            # WHERE clause to lookup apps of this type. Differs between
            # Integration and OauthApplication types.
            match_fields_for_type = matchable_database_attributes_for(app_type)

            # The list of fields that we need from the SQL query in order to
            # populate the indexes. We don't need entire ActiveRecord models,
            # so we `pluck` out just the fields we need.
            select_fields = [:id] + T.must(match_fields_for_type)

            all_apps = all_matching_apps_for_owner(
              app_type,
              owner_field,
              owner_id,
              db_attrs_for_apps
            ).pluck(*select_fields)

            # [[1, "Some App", "some-slug", "abc123somekey"], [2, "Other App"...etc.

            # Iterate over each of the configured app's attributes and attempt to
            # find the matching app in the list of all this owner's apps that
            # we selected from the database. If we find a matching app, we
            # update the indexes.
            db_attrs_for_apps.each do |this_attrs|
              # This index is built regardless of whether the app exists in the
              # database.
              indexes[:index_of_configurations_by_alias]["#{app_type}:#{this_attrs[:alias]}"] = this_attrs[:index]

              # Under certain conditions (E.g. GHES) some apps should be
              # unavailable even though they are configured.
              next unless !!this_attrs[:available]

              # We need the intersection of database_lookup_attributes defined
              # for this app _AND_ all possible matchable fields for this type
              # of app so we know we're matching only on those attributes that
              # have been configured AND selceted from the model.
              # E.g.
              # this_attrs => { owner_id: 123, name: "Some App", slug: "some-app" }
              # match_fields_for_type => [:name, :key, :slug]
              # match_fields = [:name, :slug]
              match_fields = this_attrs.keys & match_fields_for_type

              app_id = if match_fields.any?
                attr_index_fields = match_fields.each_with_object({}) { |f, o| o[f] = select_fields.index(f) }

                matched_app = all_apps.find do |app|
                  match_fields.all? { |field| app[attr_index_fields[field]] == this_attrs[field] }
                end
                matched_app.present? && matched_app[0]
              end

              app_id = app_id || this_attrs[:id] # In _very_ rare cases, apps are configured with a hard-coded ID value. Not ideal, but here for backwards compatibility.

              next unless app_id

              # These indexes are dependent on the actual App IDs loaded from the
              # database.
              indexes[:cache_of_id_by_alias]["#{app_type}:#{this_attrs[:alias]}"] = app_id
              indexes[:index_of_configurations_by_app_id]["#{app_type}:#{app_id}"] = this_attrs[:index]
            end
          end
        end

        indexes
      end

      # Query the database for the relevant type of app
      # (Integration/OauthApplication) using ActiveRecord, to find all of the
      # apps owned by the given owner OR matching a couple of special fields.
      #
      # Returns an Array or scope of apps relevant to the given owner or apps.
      def all_matching_apps_for_owner(app_type, owner_field, owner_id, db_attrs_for_apps)
        klass = Object.const_get(app_type)

        if owner_id.nil?
          # Ideally, apps would always specify the owner/user ID because
          # it makes this process much more efficient and it should
          # generally be knowable for a privileged app. However, in this
          # case we can fall back to a query against `key` or `name`.
          # There are indexes on these fields for both Integration and
          # OauthApplication.

          all_keys = db_attrs_for_apps.map { |attr| attr[:key] }.compact
          key_only_apps = klass.where(key: all_keys)
          name_only_apps = klass.none # TODO

          key_only_apps + name_only_apps
        else
          klass.where("#{owner_field} = ?", owner_id)
        end
      end

      # These are the supported attributes for each type of app, used for
      # looking up an app in the database.
      #
      # These attributes can be configured per app under the
      # `database_lookup_attributes` key.
      #
      # Returns an Array of Symbols.
      def matchable_database_attributes_for(app_type)
        case app_type
        when "Integration"; [:name, :key, :slug]
        when "OauthApplication"; [:name, :key]
        else []
        end
      end

      # Special case accounts for seeding the database on GHES and making
      # the tests pass in that environment.
      def owner_id_or_special_owner_id(owner_id)
        case owner_id
        when :first_party_apps_owner_id; GitHub.first_party_apps_owner_id
        when :trusted_proxima_apps_owner_id; GitHub.trusted_proxima_apps_owner_id
        else owner_id
        end
      end

      # Private: Given a list of app configs, containing
      # `database_lookup_attributes`, produce a new Hash containing the
      # database lookup attributes (plus app Alias and index) grouped by owner
      # ID.
      #
      # Valid database_lookup_attributes:
      # database_lookup_attributes: { owner_id: 123, name: "Some Name" }
      # database_lookup_attributes: { owner_id: 123, slug: "some-name" }
      # database_lookup_attributes: { owner_id: :first_party_owner_id, slug: "some-name" } <- Special case token ensures fresh owner ID can be used if app is recreated during DB seeding.
      # database_lookup_attributes: { user_id: 123, name: "Some Name" }
      # database_lookup_attributes: { user_id: 123, key: "abc123somekey" }
      # database_lookup_attributes: { user_id: 123, name: "Some Name" key: "abc123somekey" }
      # database_lookup_attributes: { key: "abc123somekey" }
      #
      # Example output:
      #
      # {
      #   123 => [
      #     { owner_id: 123, name: "Some Name", alias: :some_name, index: 0 },
      #     { owner_id: 123, name: "Other Name", alias: :other_name, index: 1 },
      #   ],
      #   456 => [
      #     { owner_id: 456, name: "Some App", alias: :some_app, index: 2 },
      #     { owner_id: 456, slug: "other-name", alias: :other_app, index: 3 },
      #     { owner_id: 456, key: "abc123somekey", alias: :whaveter, index: 4 },
      #   ],
      #   ...etc.
      # }
      #
      # Returns a Hash of database lookup attrs for all apps, grouped by owner
      # ID.
      def database_lookup_attributes_grouped_by_owner(app_configs, owner_field)
        attrs_with_alias_and_index = app_configs.each_with_index.map do |attrs, i|
          alias_and_index = { alias: attrs[:alias], index: i }

          alias_and_index[:available] =
            if GitHub.enterprise?
              attrs.fetch(:available_on_ghes, true)
            else
              true
            end

          attrs[:database_lookup_attributes].merge(alias_and_index)
        end

        attrs_with_alias_and_index.group_by { |attrs| attrs[owner_field] }
      end

      # Private: preloads a single app ID based on its configured
      # database_lookup_attributes and populates indexes that are used to
      # efficiently lookup the configured app based on either its ID or alias.
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

        available =
          if GitHub.enterprise?
            app_config.fetch(:available_on_ghes, true)
          else
            true
          end

        return app_config unless !!available

        config_id = app_id_for_db_attrs(app_config[:database_lookup_attributes], type)
        if config_id
          @cache_of_id_by_alias["#{type}:#{app_config[:alias]}"] = config_id
          @index_of_configurations_by_app_id["#{type}:#{config_id}"] = index
        end
        app_config
      end

      # Private: Queries the database for an app's ID based on the database
      # lookup attributes supplied. Only used in the test environment for
      # ad-hoc configuration of the registry. Should not be used in production,
      # where we prefer batch-loading for performance reasons.
      #
      # db_lookup_attrs - Hash. A set of model attributes that can be used to
      # find the configured app.
      #
      # Returns an Integer (App ID) or nil.
      def app_id_for_db_attrs(db_lookup_attrs, app_type)
        basic_id = db_lookup_attrs[:id] # The simplest case. Sometimes we just know the ID ahead of time.
        return basic_id if basic_id.present?
        # Inheritable configurations don't define any database lookup
        # attributes. Make sure we don't accidentally lookup a random app when
        # that's the case.
        return nil if (db_lookup_attrs.keys & matchable_database_attributes_for(app_type)).empty?

        owner_field =
          case app_type
          when "Integration"; :owner_id
          when "OauthApplication"; :user_id
          end


        owner_id = owner_id_or_special_owner_id(db_lookup_attrs[owner_field])
        name = db_lookup_attrs[:name]
        key = db_lookup_attrs[:key]
        slug = db_lookup_attrs[:slug]

        where_attrs = {}.tap do |obj|
          obj[owner_field] = owner_id if owner_id.present?
          obj[:name] = name if name.present?
          obj[:key] = key if key.present?
          obj[:slug] = slug if slug.present?
        end

        klass = Object.const_get(app_type)
        apps = klass.where(where_attrs)
        apps.first&.id
      end

      # Private: ensures that the instance variables used to index app IDs and
      # their configuration locations are initialized only when required.
      def ensure_caches_initialized!
        initialize_caches! unless defined?(@index_of_configurations_by_alias) &&
          defined?(@index_of_configurations_by_app_id) &&
          defined?(@cache_of_id_by_alias) &&
          defined?(@cache_of_app_by_id)
      end

      def cached_app_id(app_alias:, type:)
        @cache_of_id_by_alias["#{type}:#{app_alias}"]
      end

      def cached_app(id:, type:)
        @cache_of_app_by_id["#{type}:#{id}"]
      end

      def initialize_caches!
        @cache_of_app_by_id = {}
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
