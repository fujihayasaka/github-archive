# typed: true
# frozen_string_literal: true

module Platform
  module Session
    # Canonical value of context[:query_owning_catalog_service] for issues.
    ISSUES_CATALOG_SERVICE = "issues"

    # Cluster subclasses accessed while resolving GraphQL queries. This is the
    # authoritative list used both by InternalGraphqlController#depends_on_clusters
    # (to declare cluster dependencies) and by .set_database_role below (to
    # route reads to replicas via connected_to_many).
    #
    # Rails multi-database cluster subclasses with their own `connects_to`
    # declaration ignore ActiveRecord::Base.connected_to(role: :reading) and
    # default to :writing. Wrapping query resolution in connected_to_many with
    # this list forces reads to the replica role across all of them.
    GRAPHQL_CLUSTERS = [
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Collab,
      ApplicationRecord::Configurations,
      ApplicationRecord::Copilot,
      ApplicationRecord::Iam,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::IssuesPullRequests,
      ApplicationRecord::Lodge,
      ApplicationRecord::Memex,
      ApplicationRecord::Migrations,
      ApplicationRecord::Mysql1,
      ApplicationRecord::Mysql2,
      ApplicationRecord::Mysql5,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Notify,
      ApplicationRecord::Permissions,
      ApplicationRecord::Repositories,
      ApplicationRecord::RepositoriesActionsChecks,
      ApplicationRecord::RepositoriesPushes,
      ApplicationRecord::Spokes,
      ApplicationRecord::Stratocaster,
      ApplicationRecord::TokenScanningService,
    ].freeze

    sig { params(query: GraphQL::Query, context: Platform::IContext).returns(GraphQL::Query::Result) }
    def self.run(query, context)
      last_operations = setup_last_operations(context)

      set_database_role(last_operations, query, context) do
        query.result
      end
    ensure
      if query.mutation? && !readonly_forced?(context)
        last_operations.store_latest_writes
      end
    end

    def self.set_database_role(last_operations, query, context, &blk)
      DatabaseSelector.instance.track_writes(last_operations) do
        if readonly_forced?(context)
          set_reading_role(&blk)
        elsif query.mutation?
          set_writing_role(&blk)
        elsif readonly_primary_forced?(context)
          set_writing_role_prevent_writes(&blk)
        elsif route_graphql_reads_to_replicas?(context)
          ActiveRecord::Base.connected_to_many(GRAPHQL_CLUSTERS, role: :reading, prevent_writes: true) do
            ::DatabaseSelector.instance.read_from_database(last_operations: last_operations, called_from: :platform_session, &blk)
          end
        else
          ::DatabaseSelector.instance.read_from_database(last_operations: last_operations, called_from: :platform_session, &blk)
        end
      end
    end

    # Whether to wrap GraphQL query resolution in connected_to_many(:reading)
    # so cluster subclasses route reads to their replicas. Returns true if any
    # per-consumer predicate matches.
    def self.route_graphql_reads_to_replicas?(context)
      issues_catalog_replica_routing_active?(context)
    end

    def self.issues_catalog_replica_routing_active?(context)
      return false if ActiveRecord::Base.single_database_cluster?
      return false unless context[:query_owning_catalog_service] == ISSUES_CATALOG_SERVICE

      FeatureFlag.vexi.enabled?(:graphql_multi_cluster_replica_routing, default: false)
    end

    def self.set_reading_role(&blk)
      ActiveRecord::Base.connected_to(role: :reading, &blk)
    end

    def self.set_writing_role(&blk)
      ActiveRecord::Base.connected_to(role: :writing, &blk)
    end

    def self.set_writing_role_prevent_writes(&blk)
      ActiveRecord::Base.connected_to(role: :writing, prevent_writes: true, &blk)
    end

    def self.readonly_forced?(context)
      context[:force_readonly]
    end

    def self.readonly_primary_forced?(context)
      context[:force_readonly_primary]
    end

    def self.setup_last_operations(context)
      if (request_token = context[:request_token])
        DatabaseSelector::LastOperations.from_token(request_token)
      elsif (session = context[:session])
        DatabaseSelector::LastOperations.from_session(session, context[:cookies])
      end
    end
  end
end
