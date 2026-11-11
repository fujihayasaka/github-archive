# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class Status < Platform::Objects::Base
      description "Represents a commit status."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, status)
        repo = status.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:read_status, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rs, :repo_id, :status_oid]], as: "STA", uses_database_id: false, ready_date: Platform::Helpers::GlobalId::COHORT_5 do |status|
        {
          prefix: :rs,
          repo_id: status.repository.id,
          status_oid: status.sha,
        }
      end

      field :commit, Objects::Commit, description: "The commit this status is attached to.", null: true

      def commit
        Loaders::GitObject.load(@object.repository, @object.sha, expected_type: :commit)
      end

      field :state, Enums::StatusState, "The combined commit status.", null: false

      field :contexts, [StatusContext], description: "The individual status contexts for this commit.", null: false

      def contexts
        contexts = @object.latest_statuses_by_context
        Promise.all(contexts.map(&:async_creator)).then do |creators|
          spammy_creators = creators.collect { |c| c&.spammy? ? c.id : nil }.compact
          contexts = contexts.reject { |c| spammy_creators.include?(c.creator_id) }
          contexts.sort_by(&:sort_order)
        end
      end

      field :combined_contexts, Connections.define(Unions::StatusCheckRollupContext), description: "A list of status contexts and check runs for this commit.", null: false, connection: true

      def combined_contexts
        @object.async_contexts_with_no_spammy_creators.then do |contexts|
          ArrayWrapper.new(contexts)
        end
      end

      field :context, StatusContext, resolver_method: :status_context, description: "Looks up an individual status context by context name.", null: true do
        argument :name, String, "The context name.", required: true
      end

      def status_context(**args)
        @object.statuses.find { |status| status.context == args[:name] }
      end

      def self.load_from_next_global_id(parsed_id)
        repo_id = parsed_id.parts[:repo_id]
        oid     = parsed_id.parts[:status_oid]

        Loaders::ActiveRecord.load(::Repository, repo_id).then do |repo|
          load_from_repo_and_oid(repo, oid)
        end
      end

      def self.load_from_global_id(id)
        repo_id, oid = id.split(":", 2)

        Loaders::ActiveRecord.load(::Repository, repo_id.to_i).then do |repo|
          load_from_repo_and_oid(repo, oid)
        end
      end

      def self.load_from_repo_and_oid(repo, oid)
        Loaders::Statuses.load(repo, oid).then do |commit_statuses|
          if commit_statuses.any?
            ::CombinedStatus.new(repo, oid, statuses: commit_statuses, check_runs: [])
          else
            nil
          end
        end
      end
    end
  end
end
