# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCheckSuite < Platform::Mutations::Base
      class NoPushError < StandardError; end

      include Platform::Helpers::CommitValidation

      description "Create a check suite"

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The Node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :name, String, "The creator-supplied name for the CheckSuite. Currently only used by GitHub Actions, where it is the workflow name.", required: false, visibility: :internal
      argument :event, String, "The event that prompted this check suite, e.g 'pull_request'. Only used by GitHub Actions.", required: false, visibility: :internal
      argument :action, String, "The action of the webhook event, e.g 'merged', 'closed', 'reopened'. Only used by GitHub Actions.", required: false, visibility: :internal
      argument :head_sha, Scalars::GitObjectID, "The SHA of the head commit.", required: true
      argument :head_branch, String, "The branch name associated with this check suite.", required: false, visibility: :internal
      argument :head_repository_id, ID, "The Node ID of the repository where the head_sha belongs to.", required: false, visibility: :internal
      argument :rerequestable, Boolean, "Whether or not the check suite should be re-requestable.", visibility: :under_development, required: false, default_value: true
      argument :check_runs_rerunnable, Boolean, "Whether ot not individual check runs in the suite should be re-runnable.", visibility: :under_development, required: false, default_value: true
      argument :explicit_completion, Boolean, "Whether or not the conclusion must be calculated as soon as all existing checks have completed.", visibility: :internal, required: false
      argument :creator_id, ID, "The Node ID of the user (could be a bot) that triggered the check suite creation.", visibility: :internal, required: false, loads: Unions::Account
      argument :external_id, String, "Used by integrators with which can create >1 check suite per sha to create suites idempotently", visibility: :internal, required: false
      argument :annotations, [Inputs::CheckAnnotationData], "The annotations that are made as part of the check suite.", visibility: :internal, required: false, default_value: []
      argument :workflow_file_path, String, "The workflow file path", visibility: :internal, required: false
      argument :workflow_name, String, "The workflow name", visibility: :internal, required: false
      argument :trigger_id, ID, "The entity that triggered the workflow run.", visibility: :internal, required: false, loads: Interfaces::Trigger, as: :trigger
      argument :workflow_execution_graph, String, "The generated JSON representing the execution graph for the workflow run", visibility: :internal, required: false
      argument :conclusion, String, "Set the conclusion of an explicitly completed check suite", visibility: :internal, required: false
      argument :visibility, Enums::CheckSuiteVisibility, "Indicates whether the check suite should be hidden outside of the Actions tab", visibility: :internal, required: false
      argument :referenced_workflows, String, "The generated JSON containing referenced workflow file details", visibility: :internal, required: false
      argument :workflow_file_checkout_sha, Scalars::GitObjectID, "The checkout SHA of the required workflow from its source repository. Will be empty in case of non required workflows", visibility: :internal, required: false
      argument :workflow_run_tree_id, Scalars::GitObjectID, "The tree_id of the commit that workflow run runs on", visibility: :internal, required: false
      argument :workflow_file_ref, String, "The workflow ref of the workflow run", visibility: :internal, required: false

      error_fields
      field :check_suite, Objects::CheckSuite, "The newly created check suite.", null: true

      extras [:execution_errors]

      read_arguments_from_replicas!(require_client_permission: true, enable_selective_writes: true)

      resolve_tenant_context do |repo:, **_|
        _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(repo)
        Repositories::Public.resolve_tenant(id: repo_id)
      end

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, repo:, **inputs)
        permission.async_owner_if_org(repo).then do |org|
          permission.access_allowed?(:write_check_suite, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def resolve(repo:, execution_errors:, **inputs)
        head_sha = inputs[:head_sha]
        head_repository_id = inputs[:head_repository_id]

        if head_repository_id
          # The head repository may be a fork to which the GitHub Actions app
          # token doesn't have direct access, so we look up directly by
          # database ID.
          _, repo_id = Platform::Helpers::NodeIdentification.from_global_id(head_repository_id)

          head_repo = Repositories::Public.find_active(repo_id)
          if head_repo.nil?
            raise Platform::Errors::NotFound, "Could not resolve to Repository '#{head_repository_id}'."
          end
        end

        find_commit!(repo, head_sha)

        annotations = inputs[:annotations] || []

        if annotations.size > Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST
          return {
            check_suite: nil,
            errors: [{
              path: %w[input annotations],
              message: "Annotations exceeds a maximum quantity of #{Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST}",
            }],
          }
        end

        push = Repositories.domain.pushes.by_repo_id_and_after(after: head_sha, repository_id: (head_repo || repo).id)

        GitHub.dogstats.increment("checks.create_suite.nil_push", tags: ["where:gql"]) unless push
        head_branch = inputs[:head_branch].presence || push&.branch_name

        new_check_suite_attrs = {
          name: inputs[:name],
          event: inputs[:event],
          push_id: push&.id,
          head_sha: head_sha,
          head_branch: head_branch,
          head_repository_id: head_repo&.id,
          github_app: context[:integration],
          repository: repo,
          external_id: inputs[:external_id],
          rerequestable: inputs.key?(:rerequestable) ? inputs[:rerequestable] : true,
          check_runs_rerunnable: inputs.key?(:check_runs_rerunnable) ? inputs[:check_runs_rerunnable] : true,
          explicit_completion: inputs.key?(:explicit_completion) ? inputs[:explicit_completion] : false,
          creator: inputs[:creator],
          workflow_file_path: inputs[:workflow_file_path],
        }

        if inputs.key?(:workflow_file_path)
          referenced_workflows_json = inputs[:referenced_workflows]
          new_check_suite_attrs[:name] = process_check_suite_name(inputs[:name], inputs[:workflow_file_path])

          new_check_suite_attrs[:workflow_run_data] = Actions::WorkflowRunData.new({
            action: inputs[:action],
            workflow_name_hint: inputs[:workflow_name], # check_suite.workflow_name exists, so using workflow_name_hint instead
            workflow_execution_graph: inputs[:workflow_execution_graph],
            trigger: inputs[:event] == "push" ? push : inputs[:trigger],
            workflow_file_checkout_sha: inputs[:workflow_file_checkout_sha],
            workflow_run_execution_data: Actions::WorkflowRunExecutionData.new({
              # launch returns "" when there is an error or no referenced workflows, but we want NULL in the database in these cases
              referenced_workflows: referenced_workflows_json.blank? ? nil : referenced_workflows_json,
            }),
            tree_id: inputs[:workflow_run_tree_id],
            workflow_file_ref: inputs[:workflow_file_ref]
          })
        end

        if inputs[:conclusion].present? && new_check_suite_attrs[:explicit_completion]
          new_check_suite_attrs[:conclusion] = inputs[:conclusion]
          new_check_suite_attrs[:status] = "completed"
          new_check_suite_attrs[:completed_at] = Time.zone.now
        end

        new_check_suite_attrs[:annotations] = annotations.map do |annotation|
          check_annotation = CheckAnnotation.new(Inputs::CheckAnnotationData.hash_from_input(annotation))
          check_annotation.repository = repo
          check_annotation
        end

        with_write(clusters: [ApplicationRecord::RepositoriesActionsChecks]) do
          result = CheckSuite.find_or_create_for_integrator(new_check_suite_attrs)

          if result.success?
            # By default we calculate the hidden attribute based on the event type.
            # If the mutation passes the visibility attribute, we set the value
            # based on what the caller requests.
            case inputs[:visibility]
            when T.must(Enums::CheckSuiteVisibility.values["VISIBLE"]).value
              result.record.update!(hidden: false)
            when T.must(Enums::CheckSuiteVisibility.values["HIDDEN"]).value
              result.record.update!(hidden: true)
            end if inputs[:visibility].present?

            { check_suite: result.record, errors: [] }
          else
            if result.duplicate_for_sha?
              raise Platform::Errors::Unprocessable.new("A check suite already exists for this sha")
            end
            if result.conflict?
              raise Platform::Errors::Unprocessable.new("The check suite could not be created due to conflicting resources")
            end
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(result.record, execution_errors)
            { check_suite: nil, errors: Platform::UserErrors.mutation_errors_for_model(result.record)  }
          end
        end
      end

      private

      # We should process the check suite name when it is the same
      # as the workflow file path only in case of required workflows.
      # This is because we include additional metadata in Launch for
      # required workflow file paths and we must remove them.If not,
      # the metadata would show up in the UI/APIs along with the name.
      # This could happen when,
      #
      # 1. The workflow yaml doesn't contain an explicit `name:`
      # 2. Launch sends back the path instead of the name
      #    during error check suite creation for invalid workflows
      def process_check_suite_name(name, path)
        return name unless path.starts_with?(Actions::Workflow::REQUIRED_WORKFLOWS_BASE_PATH)

        # For required workflows, we check if the name is actually a
        # file path of the format `required/<repo_id>/<path>.yml`
        return name unless Actions::Workflow::REQUIRED_WORKFLOWS_PATH_METADATA_REGEX.match?(name)

        split_name = name.split("/")
        split_name.slice!(0..1)

        split_name.join("/")
      end
    end
  end
end
