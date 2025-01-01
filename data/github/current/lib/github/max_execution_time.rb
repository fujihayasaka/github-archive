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

    # Check this issue before updating those values https://github.com/github/databases/issues/2093
    MAX_EXECUTION_TIME = 9000
    NEW_MAX_EXECUTION_TIME = 8000

    included do
      T.bind(self, T.class_of(ApplicationRecord::Base))

      def self.max_execution_time_enabled_ff_name
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecesary overhead

        @normalized_cluster_name ||= cluster_name.to_s.tr("-", "_")
        @max_execution_time_feature_flag_name ||= "vitess_append_max_execution_time_comment_#{@normalized_cluster_name}".to_sym
      end

      def self.max_execution_time_new_timeout_ff_name
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecesary overhead

        @normalized_cluster_name ||= cluster_name.to_s.tr("-", "_")
        @max_execution_time_use_new_timeout_feature_flag_name ||= "vitess_use_new_max_execution_time_#{@normalized_cluster_name}".to_sym
      end

      def self.append_max_execution_time_comment?
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecesary overhead
        FeatureFlag.vexi.enabled?(max_execution_time_enabled_ff_name, default: false)
      end

      def self.use_new_max_execution_time?
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecesary overhead
        FeatureFlag.vexi.enabled?(max_execution_time_new_timeout_ff_name, default: false)
      end

      def self.max_execution_time
        T.bind(self, T.untyped) # this is a hot path so we disable sorbet to avoid unnecesary overhead

        if use_new_max_execution_time?
          @new_max_execution_time ||= self.const_get :NEW_MAX_EXECUTION_TIME
        else
          @max_execution_time ||= self.const_get :MAX_EXECUTION_TIME
        end
      end

      unless ActiveRecord::Base.single_database_cluster?
        default_scope -> {
          return self unless T.unsafe(self).append_max_execution_time_comment?

          T.unsafe(self).limit_execution_time(limit_ms: T.unsafe(self).max_execution_time)
        }
      end
    end
  end
end
