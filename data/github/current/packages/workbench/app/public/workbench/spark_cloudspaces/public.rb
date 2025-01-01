# typed: strict
# frozen_string_literal: true

module Workbench
  module SparkCloudspaces
    module Public

      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          spark_id: String,
          operation: Codespaces::AsyncOperation,
          devcontainer_path: T.nilable(String),
          sku_name: T.nilable(String),
          vscs_target: T.nilable(T.any(String, Symbol)),
          vscs_target_url: T.nilable(String),
          template_repository_id: T.nilable(Integer),
        ).returns(IFindOrCreateResult)
      end
      def self.find_or_create(
        owner:,
        repository_id:,
        spark_id:,
        operation:,
        devcontainer_path: nil,
        sku_name: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        template_repository_id: nil
      )
        FindOrCreate.call(
          owner:,
          repository_id:,
          template_repository_id:,
          spark_id:,
          operation:,
          devcontainer_path:,
          sku_name:,
          vscs_target:,
          vscs_target_url:,
        )
      end

      sig do
        params(
          owner: ::User,
          cloudspace_guid: String,
          repository_id: Integer,
          cap_filter: ConditionalAccess::Web::Filter,
          operation: Codespaces::AsyncOperation,
          entry_point: T.nilable(String),
        ).returns(ICodespaceResult)
      end
      def self.start(
        owner:,
        cloudspace_guid:,
        repository_id:,
        cap_filter:,
        operation:,
        entry_point: nil
      )
        Start.call(
          owner:,
          cloudspace_guid:,
          repository_id:,
          cap_filter:,
          operation:,
          entry_point:,
        )
      end

      sig { returns(Dials::MaximumInstancesForFreeUser) }
      def self.max_instances_for_free_user_global_setting
        SparkCloudspaces::Dials::MaximumInstancesForFreeUser.new(force_cache_miss: true)
      end

      sig { returns(Dials::MaximumInstancesForPaidUser) }
      def self.max_instances_for_paid_user_global_setting
        SparkCloudspaces::Dials::MaximumInstancesForPaidUser.new(force_cache_miss: true)
      end

      sig { returns(Dials::IdleTimeout) }
      def self.idle_timeout_global_setting
        SparkCloudspaces::Dials::IdleTimeout.new(force_cache_miss: true)
      end

      sig { returns(Dials::SparkWorkbenchFreeUserUsageLimitSeconds) }
      def self.free_user_usage_limit_seconds_global_setting
        SparkCloudspaces::Dials::SparkWorkbenchFreeUserUsageLimitSeconds.new(force_cache_miss: true)
      end

      sig { returns(Dials::SparkWorkbenchPaidUserUsageLimitSeconds) }
      def self.paid_user_usage_limit_seconds_global_setting
        SparkCloudspaces::Dials::SparkWorkbenchPaidUserUsageLimitSeconds.new(force_cache_miss: true)
      end

      sig { returns(Dials::SparkWorkbenchExtendedUserUsageLimitSeconds) }
      def self.extended_user_usage_limit_seconds_global_setting
        SparkCloudspaces::Dials::SparkWorkbenchExtendedUserUsageLimitSeconds.new(force_cache_miss: true)
      end
    end
  end
end
