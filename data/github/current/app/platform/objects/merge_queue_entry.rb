# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class MergeQueueEntry < Platform::Objects::Base
      description "Entries in a MergeQueue"
      visibility :public, environments: [:dotcom, :enterprise]

      implements_node templates: [[:mqe, :repository_id, :pull_request_id, :queue_id, :id]], as: "MQE", ready_date: "1970-01-01" do |mqe|
        Promise.all(
          [
            mqe.async_repository,
            mqe.async_pull_request,
            mqe.async_queue,
          ]
        ).then do |repo, pr, queue|
          {
            prefix: :mqe,
            repository_id: repo.id,
            pull_request_id: pr.id,
            queue_id: queue.id,
            id: mqe.id,
          }
        end
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, merge_queue_entry)
        permission.load_pull_and_issue(merge_queue_entry).then do |pull|
          permission.async_repo_and_org_owner(pull).then do |repo, org|
            pull.async_issue.then do |_issue|
              permission.access_allowed?(
                :get_merge_queue_entry,
                repo: repo,
                resource: pull,
                current_org: org,
                allow_integrations: true,
                allow_user_via_granular_actor: true
              )
            end
          end
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, merge_queue_entry)
        permission.belongs_to_repository(merge_queue_entry)
      end

      scopeless_tokens_as_minimum

      field :pull_request, Objects::PullRequest, description: "The pull request that will be added to a merge group",
        null: true, method: :async_pull_request
      field :merge_queue, Objects::MergeQueue, description: "The merge queue that this entry belongs to",
        null: true, method: :async_queue
      field :state, Enums::MergeQueueEntryState, description: "The state of this entry in the queue",
        null: false

      def state
        queued = T.must(Enums::MergeQueueEntryState.values["QUEUED"]).value

        begin
          @object.entry_state.const_get(:GRAPHQL_ENUM_VALUE).to_s
        rescue ArgumentError, NameError => exception
          Failbot.report(exception)
          queued
        end
      end

      field :locked, Boolean, description: "Entry is locked to deploy before merging. Locked entries will not be modified by the merge queue engine.", null: false,
        method: :locked?,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } }
      field :solo, Boolean, description: "Does this pull request need to be deployed on its own", null: false,
        method: :solo?
      field :is_solo, Boolean, description: "Does this pull request need to be deployed on its own", null: false,
        method: :solo?,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`isSolo` will be removed.",
          superseded_by: "Use `solo` instead.",
          owner: "github/merge_queue"
        }
      field :jump, Boolean, description: "Whether this pull request should jump the queue", null: false,
        method: :jump_queue?
      field :has_jumped_queue, Boolean, description: "Whether this pull request has jumped the queue.", null: false,
        method: :jump_queue?,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`hasJumpedQueue` will be removed.",
          superseded_by: "Use `jump` instead.",
          owner: "github/merge_queue"
        }
      field :enqueuer, Interfaces::Actor, description: "The actor that enqueued this entry",
        null: false, method: :async_enqueuer
      field :position, Integer, description: "The position of this entry in the queue",
        null: false

      # TODO: Remove this once we're off the legacy engine.
      def position
        @object.async_position.then do |position|
          position || 0
        end
      end

      field :estimated_time_to_merge, Integer,
        description: "The estimated time in seconds until this entry will be merged",
        null: true, method: :async_time_to_merge_in_seconds
      field :enqueued_at, Scalars::DateTime,
        description: "The date and time this entry was added to the merge queue",
        null: false
      field :blocked_by_merge_conflicts, Boolean,
        description: "Is this entry blocked from merging by a conflict?",
        null: false,
        method: :async_blocked_by_merge_conflicts?,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`blockedByMergeConflicts` will be removed.",
          superseded_by: "Use `state` instead.",
          owner: "github/merge_queue"
        }
      field :check_status, Enums::MergeQueueCheckState,
        description: "The check status for this entry. It can either represent the status of the merge group it's in or the pull request if the entry is queued as solo",
        null: false,
        method: :async_status_check_rollup_state,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`checkStatus` will be removed.",
          superseded_by: "Use `state` instead.",
          owner: "github/merge_queue"
        }
      field :head_oid, Scalars::GitObjectID, description: "The head OID/SHA for this entry",
        null: true,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`headOid` will be removed.",
          superseded_by: "Use `headCommit` instead.",
          owner: "github/merge_queue"
        }

      def head_oid
        @object.head_sha
      end

      field :head_commit, Objects::Commit, description: "The head commit for this entry", null: true

      def head_commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.head_sha, expected_type: :commit)
        end
      end

      field :base_oid, Scalars::GitObjectID, description: "The base OID/SHA for this entry",
        null: true,
        feature_flag: :merge_queue,
        visibility: { public: { environments: [:dotcom] } },
        deprecated: {
          start_date: Date.new(2023, 01, 31),
          reason: "`baseOid` will be removed.",
          superseded_by: "Use `baseCommit` instead.",
          owner: "github/merge_queue"
        }

      def base_oid
        @object.base_sha
      end

      field :base_commit, Objects::Commit, description: "The base commit for this entry", null: true

      def base_commit
        @object.async_repository.then do |repository|
          Loaders::GitObject.load(repository, @object.base_sha, expected_type: :commit)
        end
      end
    end
  end
end
