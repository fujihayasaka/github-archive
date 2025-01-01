# typed: true
# frozen_string_literal: true

require "trilogy"
require "github-trilogy-adapter"
require "resilient/trilogy"
require "github/trilogy_factory"
require "erb"
require "active_support/lazy_load_hooks"

require "application_record"

module GitHub
  module Config
    module Mysql
      extend T::Helpers
      requires_ancestor { Kernel }
      def load_activerecord
        require "active_record"
        # Anytime ActiveRecord is loaded, we also want the ds extensions loaded.
        require "github/ds_extensions"
        require_relative "../../../config/initializers/active_record_connection_class"

        if ActiveRecord::Base.configurations.empty?
          ActiveRecord::Base.configurations = database_yml
          ApplicationRecord::Mysql1.connects_to_mysql1
        end
      end

      # An Array of models whose connections use the schema cache. Only models
      # calling `connects_to` should be in this list.
      def schema_cached_models
        return @schema_cached_models if defined? @schema_cached_models

        @schema_cached_models = [
          ApplicationRecord::ActionsEnvironments,
          ApplicationRecord::Authnd,
          ApplicationRecord::Assets,
          ApplicationRecord::Ballast,
          ApplicationRecord::Billing,
          ApplicationRecord::Memex,
          ApplicationRecord::Collab,
          ApplicationRecord::Configurations,
          ApplicationRecord::Copilot,
          ApplicationRecord::Gitbackups,
          ApplicationRecord::GitHubModels,
          ApplicationRecord::Iam,
          ApplicationRecord::IamAbilities,
          ApplicationRecord::IssuesPullRequests,
          ApplicationRecord::Lodge,
          ApplicationRecord::Migrations,
          ApplicationRecord::Mysql1,
          ApplicationRecord::Mysql2,
          ApplicationRecord::Mysql5,
          ApplicationRecord::Notify,
          ApplicationRecord::NotificationsEntries,
          ApplicationRecord::NotificationsSummaries,
          ApplicationRecord::Pages,
          ApplicationRecord::Permissions,
          ApplicationRecord::SignupFlow,
          ApplicationRecord::InProductTargeting,
          ApplicationRecord::Spokes,
          ApplicationRecord::Stratocaster,
          ApplicationRecord::Repositories,
          ApplicationRecord::RepositoriesActionsChecks,
          ApplicationRecord::RepositoriesPushes,
          ApplicationRecord::TokenScanningService,
          ApplicationRecord::SecurityOverviewAnalytics,
          ApplicationRecord::SecurityProductsEnablement,
        ]

        @schema_cached_models
      end

      # Returns the database configuration for the given `name:` and
      # current `GitHub::AppEnvironment.env`.
      def database_config(name: nil)
        config = (name && database_yml[GitHub::AppEnvironment.env][name.to_s]) || database_yml[GitHub::AppEnvironment.env]["mysql1_primary"]
        config.symbolize_keys
      end

      def database_yml
        YAML.safe_load(ERB.new(File.read("#{GitHub::AppEnvironment.root}/config/database.yml")).result, aliases: true)
      end

      module AlternateConnections
        extend T::Helpers
        requires_ancestor { T.class_of(ActiveRecord::Base) }

        # Enterprise doesn't support multi-db except for a read replica.
        # We need to treat it slightly differently than the other databases
        # by allowing the other roles to get set for mysql1, but not for the
        # other databases.
        def connects_to_mysql1
          if GitHub::AppEnvironment.production?
            if GitHub.single_or_multi_tenant_enterprise?
              # Enterprise offerings don't have an entry for mysql1_readonly_slow. mysql1_readonly is available explicitly for GHEC dotcom.
              connects_to database: { writing: :mysql1_primary, reading: :mysql1_readonly, reading_slow: :mysql1_readonly }
            else
              connects_to database: { writing: :mysql1_primary, reading: :mysql1_readonly, reading_slow: :mysql1_readonly_slow }
            end
          else
            # Dev and test only have a mysql1_primary entry
            #
            # We don't call `connects_to_same` because we need the `mysql1`
            # connections to create the handlers and setup inital connections.
            connects_to database: { writing: :mysql1_primary, reading: :mysql1_primary, reading_slow: :mysql1_primary }
          end
        end

        def connects_to(database: {})
          return if !primary_class? && single_database_cluster?

          if GitHub::AppEnvironment.production? || primary_class?
            super(database: database)
          else
            connects_to_same(database: database[:writing])
          end
        end

        def connects_to_same(database:, name: nil)
          raise NotImplementedError, "must not be called in production" if GitHub::AppEnvironment.production?
          return if single_database_cluster? && name.nil?

          unless name.nil?
            configs = ActiveRecord::Base.configurations
            base_config = configs.resolve(database)
            config = ActiveRecord::DatabaseConfigurations::HashConfig.new(base_config.env_name, name.to_s, base_config.configuration_hash)
            ActiveRecord::Base.configurations = ActiveRecord::DatabaseConfigurations.new(configs.configurations.append(config))
            database = name
          end

          connection_name_to_pool_manager = T.let(nil, T.untyped)
          writing_conn_proc = proc do
            establish_connection(database)
            connection_name_to_pool_manager = connection_handler.instance_variable_get(:@connection_name_to_pool_manager).fetch(connection_specification_name).get_pool_config(:writing, :default)
          end

          reading_conn_proc = proc do
            connection_handler.instance_variable_get(:@connection_name_to_pool_manager)[connection_specification_name].set_pool_config(:reading, :default, connection_name_to_pool_manager)
          end

          reading_slow_conn_proc = proc do
            connection_handler.instance_variable_get(:@connection_name_to_pool_manager)[connection_specification_name].set_pool_config(:reading_slow, :default, connection_name_to_pool_manager)
          end

          self.connection_class = true

          ActiveRecord::Base.connected_to(role: :writing, &writing_conn_proc)
          ActiveRecord::Base.connected_to(role: :reading, &reading_conn_proc)

          if connection_specification_name.to_s == "ApplicationRecord::Repositories" || connection_specification_name.to_s == "ApplicationRecord::IssuesPullRequests"
            ActiveRecord::Base.connected_to(role: :reading_slow, &reading_slow_conn_proc)
          end
        end

        def connected_to(role: nil, prevent_writes: false, &blk)
          if role == :reading_slow
            # Only when called from a console:
            if $console && GitHub::AppEnvironment.production?
              warn ""
              warn "Sorry, slow mysql queries aren't allowed from the console!"
              warn "Use the console-specific connection for slow queries:"
              warn ""
              warn "$ gh-dbconsole slow"
              warn ""
              return
            end
          end

          super
        end

        def connect_all_to_same
          raise "must only be called in test" unless GitHub::AppEnvironment.test?

          ActiveRecord::Base.establish_connection :mysql1_primary # rubocop:disable GitHub/DoNotCallMethodsOnActiveRecordBase

          ApplicationRecord::Mysql1.connects_to_mysql1
          ApplicationRecord::ActionsEnvironments.connects_to_same database: :actions_environments_primary
          ApplicationRecord::Assets.connects_to_same database: :assets_primary
          ApplicationRecord::Authnd.connects_to_same database: :authnd_primary
          ApplicationRecord::Ballast.connects_to_same database: :ballast_primary
          ApplicationRecord::Billing.connects_to_same database: :billing_primary
          ApplicationRecord::Collab.connects_to_same database: :collab_primary
          ApplicationRecord::Configurations.connects_to_same database: :configurations_primary
          ApplicationRecord::Copilot.connects_to_same database: :copilot_primary
          ApplicationRecord::GitHubModels.connects_to_same database: :github_models_primary
          ApplicationRecord::Iam.connects_to_same database: :iam_primary
          ApplicationRecord::IamAbilities.connects_to_same database: :abilities_primary
          ApplicationRecord::Lodge.connects_to_same database: :lodge_primary
          ApplicationRecord::Memex.connects_to_same database: :memex_primary
          ApplicationRecord::Mysql2.connects_to_same database: :notifications_primary
          ApplicationRecord::Mysql5.connects_to_same database: :kv_primary
          ApplicationRecord::Migrations.connects_to_same database: :migrations_primary
          ApplicationRecord::Notify.connects_to_same database: :notify_primary
          ApplicationRecord::NotificationsEntries.connects_to_same database: :notifications_entries_primary
          ApplicationRecord::NotificationsSummaries.connects_to_same database: :notifications_summaries_primary
          ApplicationRecord::Pages.connects_to_same database: :pages_primary
          ApplicationRecord::Permissions.connects_to_same database: :permissions_primary
          ApplicationRecord::Repositories.connects_to_same database: :repositories_primary
          ApplicationRecord::RepositoriesActionsChecks.connects_to_same database: :repositories_actions_checks_primary
          ApplicationRecord::IssuesPullRequests.connects_to_same database: :issues_pull_requests_primary
          ApplicationRecord::RepositoriesPushes.connects_to_same database: :repositories_pushes_sharded_primary
          if single_database_cluster?
            ApplicationRecord::Spokes.connects_to_same database: :mysql1_primary, name: :mysql1_primary_spokes
          else
            ApplicationRecord::Spokes.connects_to_same database: :spokes_write
          end
          ApplicationRecord::Stratocaster.connects_to_same database: :stratocaster_primary
          ApplicationRecord::TokenScanningService.connects_to_same database: :token_scanning_service_primary
          ApplicationRecord::SecurityOverviewAnalytics.connects_to_same database: :security_overview_analytics_primary
          ApplicationRecord::SignupFlow.connects_to_same database: :signup_flow_primary
          ApplicationRecord::InProductTargeting.connects_to_same database: :in_product_targeting_primary
        end

        def single_database_cluster?
          # Enterprise only has a single DB
          return true if GitHub.enterprise?
          # Multi-tenant only has a single DB in production, but multiple in dev/test
          return true if GitHub::AppEnvironment.production? && GitHub.multi_tenant_enterprise?

          false
        end
      end
    end
  end

  extend Config::Mysql
end

ActiveSupport.on_load(:active_record) do
  extend GitHub::Config::Mysql::AlternateConnections

  ActiveRecord::ConnectionAdapters::TrilogyAdapter.database_driver = GitHub::TrilogyFactory
  ActiveRecord::ConnectionAdapters::TrilogyAdapter.prepend(GitHub::ConnectionAdapterTelemetry) unless ActiveRecord::Base.single_database_cluster?
end

# See http://dev.mysql.com/doc/refman/5.0/en/storage-requirements.html
# 2^16 - 1 bytes is the limit for BLOB and TEXT fields.
# If you need longer, you should use MEDIUMBLOB or MEDIUMTEXT.
MYSQL_TEXT_FIELD_LIMIT = 65535

# This size will be backed by a MEDIUMBLOB in the database, but is
# just enough space to fit 65k 4-byte unicode characters. Esentially
# this is the binary version of a TEXT field meant to store Unicode.
MYSQL_UNICODE_BLOB_LIMIT = 262144
