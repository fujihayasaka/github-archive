# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MergeQueue < Platform::Objects::Base
      description "The queue of pull request entries to be merged into a protected branch in a repository."
      visibility :public, environments: [:dotcom, :enterprise]

      implements_node templates: [[:mq, :repository_id, :id]], as: "MQ", ready_date: "1970-01-01" do |mq|
        mq.async_repository.then do |repo|
          {
            prefix: :mq,
            repository_id: repo.id,
            id: mq.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, merge_queue)
        permission.async_repo_and_org_owner(merge_queue).then do |repo, org|
          permission.access_allowed?(
            :get_merge_queue,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, merge_queue)
        permission.belongs_to_repository(merge_queue)
      end

      scopeless_tokens_as_minimum

      url_fields description: "The HTTP URL for this merge queue" do |queue|
        queue.async_path_uri
      end

      field :repository, Objects::Repository, description: "The repository this merge queue belongs to", null: true, method: :async_repository

      field :entries, Connections.define(Objects::MergeQueueEntry), description: "The entries in the queue", null: true,
        connection: true

      def entries
        @object.async_entries.then do |merge_queue_entries|
          ArrayWrapper.new(merge_queue_entries)
        end
      end

      field :merging_entries, Connections.define(Objects::MergeQueueEntry), description: "The entries in the queue which are about to be merged", null: true,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`mergingEntries` will be removed.",
          superseded_by: nil,
          owner: "github/merge_queue"
        }

      def merging_entries
        @object.async_merging_entries.then do |entries|
          ArrayWrapper.new(entries)
        end
      end

      field :pending_removal_entries, Connections.define(Objects::MergeQueueEntry), description: "The entries in the queue which are about to be removed", null: true,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`pendingRemovalEntries` will be removed.",
          superseded_by: nil,
          owner: "github/merge_queue"
        }

      def pending_removal_entries
        ArrayWrapper.new([])
      end

      field :head_oid, Scalars::GitObjectID, "OID for the merge head of the locked group.", null: true,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`headOid` will be removed.",
          superseded_by: "Use `entry.headOid` instead.",
          owner: "github/merge_queue"
        }

      def head_oid
        @object.async_locked_entry.then do |entry|
          entry&.head_sha
        end
      end

      field :next_entry_estimated_time_to_merge, Integer,
        description: "The estimated time in seconds until a newly added entry would be merged",
        null: true, method: :next_entry_time_to_merge_in_seconds

      field :merge_method, Enums::PullRequestMergeMethod, description: "The merge method used for this merge queue", null: false,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`mergeMethod` will be removed.",
          superseded_by: "Use `configuration.merge_method` instead.",
          owner: "github/merge_queue"
        }

      def merge_method
        @object.merge_method.to_sym
      end

      field :configuration, Objects::MergeQueueConfiguration, description: "The configuration for this merge queue", null: true

      def configuration
        config = MergeQueues.configuration_for(@object)
        {
          merge_queue: @object,
          merge_method: config.merge_method.serialize,
          maximum_entries_to_build: config.max_concurrency,
          minimum_entries_to_merge: config.min_merge_entries_size,
          minimum_entries_to_merge_wait_time: config.max_wait_for_min_merge_entries_size,
          maximum_entries_to_merge: config.max_merge_entries_size,
          check_response_timeout: config.check_response_timeout,
          merging_strategy: config.grouping_strategy.serialize,
        }
      end
    end
  end
end
