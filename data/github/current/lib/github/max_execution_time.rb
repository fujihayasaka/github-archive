# typed: true
# frozen_string_literal: true

# This module is used to set the max execution time for Vitess queries to make it compatible with mysql's behavior
# because vitess doesn't support the max_execution_time session variable yet - https://github.com/vitessio/vitess/issues/9236
#
# It adds the following comment to each vitess SELECT query, for models including it.
# /*+ MAX_EXECUTION_TIME([max_execution_time_ms]) */
# eg:
#   SELECT * FROM table WHERE id = 1;
# becomes:
#   SELECT /*+ MAX_EXECUTION_TIME(1000) */ * FROM table WHERE id = 1;
module GitHub
  module MaxExecutionTime
    extend ActiveSupport::Concern
    extend T::Helpers

    requires_ancestor { ApplicationRecord::Base }

    # Per-cluster baseline timeouts in milliseconds. To change a cluster's timeout, edit its
    # entry here. To add a new cluster, add a new key matching the normalized cluster name
    # (dashes replaced with underscores). Unknown clusters fall back to DEFAULT_TIMEOUT.
    DEFAULT_TIMEOUT = 8_000

    CLUSTER_TIMEOUTS = {
      "issues_pull_requests" => 8_000,
      "repositories" => 8_000,
      "billing" => 8_000,
      "notifications_entries" => 8_000,
      "pages" => 8_000,
      "permissions" => 8_000,
      "repositories_actions_checks" => 8_000,
      "repositories_pushes_sharded" => 8_000,
      "token_scanning_service_prod" => 8_000,
      "lodge" => 8_000,
    }.freeze

    # Roles that serve web/API requests and should have MAX_EXECUTION_TIME applied.
    # Non-request processes (jobs, aqueduct workers, stream processors, consoles, cron) should be excluded.
    # This mirrors the pattern in database.yml and kustomize with MYSQL_MAX_EXECUTION_TIME_* env vars by deployment.
    REQUEST_SERVING_ROLES = Set[:fe, :api, :stafftools, :lab].freeze

    included do
      T.bind(self, T.class_of(ApplicationRecord::Base))

      def self.max_execution_time_enabled_ff_name
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecessary overhead

        @normalized_cluster_name ||= cluster_name.to_s.tr("-", "_")
        @max_execution_time_feature_flag_name ||= "vitess_append_max_execution_time_comment_#{@normalized_cluster_name}".to_sym
      end

      def self.append_max_execution_time_comment?
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecessary overhead
        FeatureFlag.vexi.enabled?(max_execution_time_enabled_ff_name, default: false)
      end

      def self.max_execution_time
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecessary overhead

        @cluster_timeout ||= self.const_get(:CLUSTER_TIMEOUTS).fetch(
          cluster_name.to_s.tr("-", "_"),
          self.const_get(:DEFAULT_TIMEOUT)
        )
      end

      def self.request_serving_role?
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecessary overhead
        REQUEST_SERVING_ROLES.include?(GitHub.role)
      end

      unless ActiveRecord::Base.single_database_cluster?
        default_scope -> {
          return self unless T.unsafe(self).append_max_execution_time_comment?
          return self unless T.unsafe(self).request_serving_role?

          T.unsafe(self).limit_execution_time(limit_ms: T.unsafe(self).max_execution_time)
        }
      end
    end
  end
end
