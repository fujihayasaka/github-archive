# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ReusePreviousWorkflowRun < Platform::Mutations::Base
      class NoPushError < StandardError; end

      include Platform::Helpers::CommitValidation
      include Platform::Helpers::GitHubAppValidation

      description "Reuse a workflow run result in another commit"
      visibility :internal

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :check_suite_to_clone, ID, "The node ID of the check suite that will be cloned to create a new workflow run.", required: true, visibility: :internal, loads: Objects::CheckSuite, as: :check_suite
      argument :event, String, "The event that prompted this reuse, e.g 'pull_request'. Only used by GitHub Actions.", required: true, visibility: :internal
      argument :creator_id, ID, "The Node ID of the user (could be a bot) that triggered the event", required: true, visibility: :internal, loads: Unions::Account, as: :creator
      argument :trigger_id, ID, "The entity that triggered the workflow run.", required: false, visibility: :internal, loads: Interfaces::Trigger, as: :trigger
      argument :head_sha, Scalars::GitObjectID, "The head_sha of the new check suite that will be created.", required: true, visibility: :internal
      argument :head_branch, String, "The branch name associated with the new check suite that will be created.", required: false, visibility: :internal
      argument :tree_id, Scalars::GitObjectID, "The tree_id of the existing workflow run that will be reused", required: true, visibility: :internal

      resolve_tenant_context do |repo:, **_|
        _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(repo)
        Repositories::Public.resolve_tenant(id: repo_id)
      end

      field :check_suite, Objects::CheckSuite, "The new cloned check suite as part of the reused workflow run", null: true
      error_fields

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_check_suite, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(check_suite:, repo:, **inputs)
        if repo.id != check_suite.repository_id
          # Effectively, a 404, the check suites should be within the same repository
          raise Platform::Errors::NotFound.new("Could not resolve check suite `#{check_suite.global_relay_id}` to repository `#{repo.global_relay_id}`")
        end

        unless allowed_to_modify_app?(app_id: check_suite.github_app_id)
          # Effectively, a 403, information will be shared between cloned/reused check suites & workflow runs so permission boundaries must be maintained
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_suite.global_relay_id}`")
        end

        creator = inputs[:creator]
        unless GitHub.flipper[:actions_green_trees].enabled?(repo) || GitHub.flipper[:actions_green_trees].enabled?(creator)
          raise Platform::Errors::Forbidden.new("actions_green_trees is not enabled for repository or user")
        end

        event_type = inputs[:event]
        unless Actions::WorkflowRun::SUPPORTED_REUSE_EVENT_TYPES.include?(event_type)
          raise Platform::Errors::Forbidden.new("Event #{event_type} is not supported for reuse")
        end

        # For push events, Launch doesn't receive the trigger event in the webhook payload so we have to find it ourselves
        # See https://github.com/github/launch/blob/85707d33f2f2efdc6c214e9aa037fad027726f78/services/deploy/workflowinvoker/build_invoker.go#L916
        event_trigger = inputs[:trigger]
        head_sha = inputs[:head_sha]
        if event_type == "push"
          event_trigger = Repositories.domain.pushes.by_repo_id_and_after(after: head_sha, repository_id: repo.id)
        end

        check_run_count = check_suite.check_runs.count

        GitHub.dogstats.increment("actions.workflow_run.reuse_previous_workflow_run.begin")
        GitHub.logger.info(
          "Begin workflow run reuse",
          {
            "code.namespace" => self.class.name,
            "code.function" => "resolve",
            "gh.catalog_service" => "github/actions",
            "gh.request_id" => GitHub.context[:request_id],
            "gh.repository.id" => check_suite.repository_id,
            "gh.check_suite.original.id" => check_suite.id,
            "gh.check_suite.check_runs.count" => check_run_count
          }
        )

        cloned_check_suite = Actions::PreviousOutcomeReuse.call(
          existing_check_suite_to_clone: check_suite,
          clone_check_suite_head_sha: head_sha,
          clone_trigger: event_trigger,
          clone_creator: creator,
          clone_event: event_type,
          clone_head_branch: inputs[:head_branch],
          tree_id: inputs[:tree_id],
        )

        if cloned_check_suite.present?
          GitHub.dogstats.increment("actions.workflow_run.reuse_previous_workflow_run.success")
          GitHub.dogstats.count("actions.workflow_run.reuse_previous_workflow_run.success.check_run_count", check_run_count)

          # Check run duration is different from billable duration but nevertheless we can use this as an approximated
          # metric to gauge how much time we're saving by being to able to just copy over from the previous check runs
          approximate_saved_duration_seconds = check_suite.check_runs.map(&:duration).sum
          approximate_saved_duration_minutes = approximate_saved_duration_seconds / 60
          GitHub.dogstats.count("actions.workflow_run.reuse_previous_workflow_run.success.duration_saved", approximate_saved_duration_minutes)

          GitHub.logger.info(
            "Workflow run successfully resused",
            {
              "code.namespace" => self.class.name,
              "code.function" => "resolve",
              "gh.catalog_service" => "github/actions",
              "gh.request_id" => GitHub.context[:request_id],
              "gh.repository.id" => check_suite.repository_id,
              "gh.check_suite.original.id" => check_suite.id,
              "gh.check_suite.clone.id" => cloned_check_suite.id,
              "gh.check_suite.check_runs.duration_saved" => approximate_saved_duration_minutes,
            }
          )
          {
            check_suite: cloned_check_suite,
            errors: []
          }
        else
          GitHub.dogstats.increment("actions.workflow_run.reuse_previous_workflow_run.failure")
          GitHub.logger.info(
            "Unable to reuse previous workflow run",
            {
              "code.namespace" => self.class.name,
              "code.function" => "resolve",
              "gh.catalog_service" => "github/actions",
              "gh.request_id" => GitHub.context[:request_id],
              "gh.repository.id" => check_suite.repository_id,
              "gh.check_suite.original.id" => check_suite.id,
            }
          )

          raise Platform::Errors::Unprocessable.new("Could not clone check suite `#{check_suite.global_relay_id}` for reuse")
        end
      end
    end
  end
end
