# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class StatusCheckRollup < Platform::Objects::Base
      description "Represents the rollup for both the check runs and status for a commit."

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        permission.typed_can_see?("Repository", object.repository)
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, object)
        repo = object.repository
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(
            :get_status_check_rollup,
            resource: repo,
            current_org: org,
            current_repo: repo,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
          )
        end
      end

      scopeless_tokens_as_minimum

      implements_node templates: [[:rscr, :repo_id, :oid]], as: "SCR", ready_date: Platform::Helpers::GlobalId::COHORT_5, uses_database_id: false do |status_check_rollup|
        {
          prefix: :rscr,
          repo_id: status_check_rollup.repository.id,
          oid: status_check_rollup.sha,
        }
      end

      field :commit, Objects::Commit, description: "The commit the status and check runs are attached to.", null: true

      def commit
        Loaders::GitObject.load(@object.repository, @object.sha, expected_type: :commit)
      end

      field :state, Enums::StatusState, "The combined status for the commit.", null: false

      field :short_text, String, "A short summary of successful and total contexts.", null: false, visibility: :internal

      field :contexts, Connections::StatusCheckRollupContext, description: "A list of status contexts and check runs for this commit.", null: false, connection: true

      def contexts
        @object.async_contexts_with_no_spammy_creators.then do |contexts|
          ArrayWrapper.new(contexts)
        end
      end

      def self.load_from_repo_and_oid(repo, oid, overview_only = false)
        if overview_only
          return Loaders::CombinedStatusOverview.load(repo, oid).then do |rows|
            states = rows.map { |row| row["conclusion"] }
            state = ::StatusCheckRollup.rollup_state(states)
            short_text = Loaders::CombinedStatusOverview.short_text(rows)
            next if short_text.nil?
            ::CombinedStatus.new(repo, oid, platform_type_name: "StatusCheckRollup", state: state, short_text: short_text)
          end
        end

        Promise.all([
          Loaders::Statuses.load(repo, oid),
          Loaders::CheckRuns.load(repo, oid),
        ]).then do |commit_statuses, check_runs|
          next if commit_statuses.empty? && check_runs.empty?
          ::CombinedStatus.new(repo, oid, statuses: commit_statuses, check_runs: check_runs, platform_type_name: "StatusCheckRollup")
        end
      end

      def self.load_from_next_global_id(parsed_id)
        Loaders::ActiveRecord.load(::Repository, parsed_id.parts[:repo_id].to_i, security_violation_behaviour: :nil).then do |repo|
          if repo
            load_from_repo_and_oid(repo, parsed_id.parts[:oid])
          end
        end
      end

      def self.load_from_global_id(id)
        repo_id, oid = id.split(":", 2)
        Loaders::ActiveRecord.load(::Repository, repo_id.to_i, security_violation_behaviour: :nil).then do |repo|
          if repo
            load_from_repo_and_oid(repo, oid)
          end
        end
      end
    end
  end
end
