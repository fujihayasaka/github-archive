# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CheckSuite < Platform::Objects::Base
      description "A check suite."

      implements_node templates: [[:rcs, :repo_id, :check_suite_id]], as: "CS", ready_date: Platform::Helpers::GlobalId::COHORT_1 do |check_suite|
        {
          prefix: :rcs,
          repo_id: check_suite.repository_id,
          check_suite_id: check_suite.id
        }
      end

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, check_suite)
        permission.async_repo_and_org_owner(check_suite).then do |repo, org|
          permission.access_allowed?(:read_check_suite, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, check_suite)
        permission.load_repo_and_owner(check_suite).then do |repo|
          repo.resources.checks.async_readable_by?(permission.viewer)
        end
      end

      scopeless_tokens_as_minimum

      database_id_field

      created_at_field

      updated_at_field

      url_fields description: "The HTTP URL for this check suite" do |check_suite|
        check_suite.async_repository.then do |repository|
          repository.async_owner.then do |owner|
            template = Addressable::Template.new("/{user}/{repo}/commit/{head_sha}/checks?check_suite_id={id}")
            template.expand user: owner.display_login, repo: repository.name, head_sha: check_suite.head_sha, id: check_suite.id
          end
        end
      end

      field :repository, Objects::Repository, "The repository associated with this check suite.", method: :async_repository, null: false

      field :check_runs, Connections.define(Objects::CheckRun), description: "The check runs associated with a check suite.", null: true, connection: true, numeric_pagination_enabled: true do
        argument :filter_by, Inputs::CheckRunFilter, "Filters the check runs by this type.", required: false
      end

      def check_runs(**arguments)
        arguments[:filter_by] ||= {}

        @object.async_repository.then do |repository|
          @object.async_github_app.then do
            filter_check_runs_relation = -> (check_runs) do
              if id = arguments[:filter_by][:app_id].presence
                check_runs = check_runs.for_app_id(id, repository.id)
              end

              if name = arguments[:filter_by][:check_name].presence
                check_runs = check_runs.where(name: name).or(check_runs.with_display_name(name))
              end

              if statuses = arguments[:filter_by][:statuses].presence
                check_runs = check_runs.where(status: statuses)
              elsif status = arguments[:filter_by][:status].presence
                check_runs = check_runs.where(status: ::CheckRun.statuses[status])
              end

              if conclusions = arguments[:filter_by][:conclusions].presence
                check_runs = check_runs.where(conclusion: conclusions)
              end

              check_runs
            end

            case arguments[:filter_by][:check_type]
            when "all"
              check_runs = @object.check_runs.annotate("cross-shard-query-exempted").order("id DESC")
              filter_check_runs_relation.call(check_runs)
            else
              # The latest_check_runs method takes a block to use add scopes before filtering.
              @object.latest_check_runs(&filter_check_runs_relation)
            end
          end
        end
      end

      field :matching_pull_requests, resolver: Resolvers::CheckSuitePullRequests, description:  "A list of open pull requests matching the check suite.", null: true

      field :branch, Ref, description: "The name of the branch for this check suite.", null: true

      def branch
        @object.async_repository.then do |repo|
          repo.async_network.then do
            repo.refs.find(@object.head_branch)
          end
        end
      end

      field :commit, Objects::Commit, description: "The commit for this check suite", null: false

      def commit
        @object.async_repository.then do |repo|
          repo.async_network.then do
            repo.commits.find(@object.head_sha)
          end
        end
      end

      field :rerequestable, Boolean, description: "Whether or not this check suite is re-requestable; DEFAULT: DO NOT USE", null: false, required_capabilities: [:mobile_only_schema_mask]

      field :check_runs_rerunnable, Boolean, description: "Whether or not the individual runs in this check suite are re-runnable; DEFAULT: DO NOT USE", null: false, required_capabilities: [:mobile_only_schema_mask]

      field :rerunnable, Boolean, description: "Whether or not this check suite is re-runnable.", null: false, required_capabilities: [:mobile_only_schema_mask]

      def rerunnable
        ## pre-load repository beause check_suite.rerunnable? depends on the object being available
        @object.async_repository.then do |_|
          if object.respond_to?(:rerunnable?)
            object.rerunnable?
          else
            false ## default to false to satisfy the field type
          end
        end
      end

      field :status, Enums::CheckStatusState, description: "The status of this check suite.", null: false

      field :conclusion, Enums::CheckConclusionState, description: "The conclusion of this check suite.", null: true

      field :push, Objects::Push, description: "The push that triggered this check suite.", method: :async_push, null: true

      field :app, App, description: "The GitHub App which created this check suite.", method: :async_github_app, null: true

      field :completed_log_url, Scalars::URI, description: "The URL to the completed logs of this check suite.", visibility: :internal, null: true

      field :artifacts, Connections.define(Objects::Artifact), description: "The check suite's artifacts", null: true, connection: true, required_capabilities: [:mobile_only_schema_mask] do
        argument :order_by, Inputs::ArtifactOrder, "Order for connection", required: false, default_value: { field: "created_at", direction: "DESC" }
      end

      def artifacts(order_by:)
        @object.artifacts.order("artifacts.#{order_by[:field]} #{order_by[:direction]}")
      end

      field :name, String, description: "The creator-supplied name for the CheckSuite. Currently only used by GitHub Actions, where it is the workflow name.", null: true, required_capabilities: [:mobile_only_schema_mask]

      field :event, String, description: "The event that prompted this check suite, e.g 'pull_request'. Only used by GitHub Actions.", null: true, required_capabilities: [:mobile_only_schema_mask]

      field :creator, Objects::User, "The user who triggered the check suite.", method: :async_creator, null: true

      field :annotations, Connections.define(Objects::CheckAnnotation), description: "The check suite's annotations", null: true, connection: true, numeric_pagination_enabled: true, visibility: :internal

      def annotations(**arguments)
        @object.annotations.scoped
      end

      field :workflow_name, String, description: "The name of the workflow with a fallback value", required_capabilities: [:mobile_only_schema_mask], null: false

      field :workflow_file_path, String, description: "The path of the workflow file", required_capabilities: [:mobile_only_schema_mask], null: true

      def workflow_file_path
        @object.workflow_file_path&.dup&.force_encoding("UTF-8")
      end

      field :workflow_run, Objects::WorkflowRun, "The workflow run associated with this check suite.", method: :async_workflow_run, null: true

      field :duration, Integer, description: "The duration of the last execution of the check suite", required_capabilities: [:mobile_only_schema_mask], null: false

      field :has_reruns, Boolean, description: "Whether or not this check suite has reruns", required_capabilities: [:mobile_only_schema_mask], null: false

      field :started_at, Scalars::DateTime, description: "The time the check suite was started.", null: true, required_capabilities: [:mobile_only_schema_mask]

      field :completed_at, Scalars::DateTime, description: "The time the check suite was completed.", null: true, required_capabilities: [:mobile_only_schema_mask]
    end
  end
end
