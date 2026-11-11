# typed: strict
# frozen_string_literal: true

module WorkspaceEditor
  module Cloudspaces
    module Public


      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          pull_request_number: Integer,
          location: String,
          operation: Codespaces::AsyncOperation,
          display_name: T.nilable(String),
          devcontainer_path: T.nilable(String),
          sku_name: T.nilable(String),
          vscs_target: T.nilable(String),
          vscs_target_url: T.nilable(String),
          entry_point: T.nilable(String),
          force_create: T::Boolean,
        ).returns(IFindOrCreateResult)
      end
      def self.create_unique(
        owner:,
        repository_id:,
        pull_request_number:,
        location:,
        operation:,
        display_name: nil,
        devcontainer_path: nil,
        sku_name: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        entry_point: nil,
        force_create: false
      )
        CreateUnique.call(
          owner:,
          repository_id:,
          pull_request_number:,
          operation:,
          location:,
          display_name:,
          devcontainer_path:,
          sku_name:,
          vscs_target:,
          vscs_target_url:,
          entry_point:,
          force_create:,
        )
      end

      sig do
        params(
          owner: ::User,
          repository_id: Integer,
          pull_request_number: Integer,
          location: String,
          operation: Codespaces::AsyncOperation,
          display_name: T.nilable(String),
          devcontainer_path: T.nilable(String),
          sku_name: T.nilable(String),
          vscs_target: T.nilable(String),
          vscs_target_url: T.nilable(String),
          entry_point: T.nilable(String)
        ).returns(IFindOrCreateResult)
      end
      def self.find_or_create(
        owner:,
        repository_id:,
        pull_request_number:,
        location:,
        operation:,
        display_name: nil,
        devcontainer_path: nil,
        sku_name: nil,
        vscs_target: nil,
        vscs_target_url: nil,
        entry_point: nil
      )
        FindOrCreate.call(
          owner:,
          repository_id:,
          pull_request_number:,
          operation:,
          location:,
          display_name:,
          devcontainer_path:,
          sku_name:,
          vscs_target:,
          vscs_target_url:,
          entry_point:
        )
      end

      sig { returns(Dials::MaximumInstancesForUser) }
      def self.max_instances_for_user_global_setting
        Cloudspaces::Dials::MaximumInstancesForUser.new(force_cache_miss: true)
      end

      sig { returns(Dials::IdleTimeout) }
      def self.idle_timeout_global_setting
        Cloudspaces::Dials::IdleTimeout.new(force_cache_miss: true)
      end

      sig { returns(T::Boolean) }
      def self.soft_deletable_global_setting
        FeatureFlag.vexi.enabled?(:hadron_cloudspaces_soft_deletable, default: false)
      end
    end
  end
end
