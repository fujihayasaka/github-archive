# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateCheckRun < Platform::Mutations::Base
      include Platform::Helpers::CommitValidation
      include Scientist

      description "Create a check run."

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :name, String, "The name of the check.", required: true
      argument :display_name, String, "Optional name that, if defined, will be used in the UI instead of the name.", required: false, visibility: :internal
      argument :head_sha, Scalars::GitObjectID, "The SHA of the head commit.", required: true

      argument :check_suite_id, ID, "The node ID of the CheckSuite to create this under.", visibility: :internal, required: false, loads: Objects::CheckSuite, as: :check_suite
      argument :details_url, Scalars::URI, "The URL of the integrator's site that has the full details of the check.", required: false
      argument :external_id, String, "A reference for the run on the integrator's system.", required: false
      argument :status, Enums::RequestableCheckStatusState, "The current status.", required: false
      argument :started_at, Scalars::DateTime, "The time that the check run began.", required: false
      argument :conclusion, Enums::CheckConclusionState, "The final conclusion of the check.", required: false
      argument :completed_at, Scalars::DateTime, "The time that the check run finished.", required: false
      argument :output, Inputs::CheckRunOutput, "Descriptive details about the run.", required: false
      argument :actions, [Inputs::CheckRunAction], "Possible further actions the integrator can perform, which a user may trigger.", required: false
      argument :steps, [Inputs::CheckStepData], "Steps this check run will execute", visibility: :internal, required: false
      argument :completed_log, Inputs::CompletedLogData, "The completed log information", visibility: :internal, required: false
      argument :job_summary, Inputs::JobSummaryData, "Summary data for workflow job", visibility: :internal, required: false
      argument :number, Int, "The topological order of the check run within the check suite.", visibility: :internal, required: false
      argument :streaming_log, Inputs::StreamingLogData, "Streaming log information", visibility: :internal, required: false
      argument :environment, String, "Deployment environment for Actions CD", visibility: :internal, required: false
      argument :job_key, String, "The job key.", visibility: :internal, required: false
      argument :parent_job_id, String, "The ID of the parent job.", visibility: :internal, required: false
      argument :concurrency, Inputs::Concurrency, "The concurency information about the check run", visibility: :internal, required: false
      argument :labels, [String], "labels to be applied to this job as a json array", visibility: :internal, required: false
      argument :runner_id, Int, "The ID of the self-hosted runner, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_group_id, Int, "The ID of the self-hosted runner group, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_name, String, "The name of the self-hosted runner, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_group_name, String, "The name of the self-hosted runner group, iff the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :is_cloned_from_previous_run, Boolean, "Indicates whether this run was cloned from a previous run for a partial rerun", visibility: :internal, required: false

      error_fields

      field :check_run, Objects::CheckRun, "The newly created check run.", null: true

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
          permission.access_allowed?(:write_check_run, resource: repo, current_repo: repo, current_org: org, allow_integrations: true, allow_user_via_granular_actor: true)
        end
      end

      def can_create_deployment?(permission, repo)
        org = context[:permission].async_owner_if_org(repo).sync
        begin
          permission.access_allowed?(:write_deployment,
            resource: repo,
            current_repo: repo,
            current_org: org,
            allow_integrations: true,
            allow_user_via_granular_actor: true)
        rescue Platform::Errors::Forbidden
          false
        end
      end

      def resolve(repo:, execution_errors:, **inputs)
        with_write(clusters: [ApplicationRecord::RepositoriesActionsChecks, ApplicationRecord::IssuesPullRequests]) do
          if inputs[:output] && inputs[:output][:annotations] && inputs[:output][:annotations].size > Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST
            return {
              check_run: nil,
              errors: [{
                "path" => %w[input output annotations],
                "message" => "Annotations exceeds a maximum quantity of #{Inputs::CheckAnnotationData::MAXIMUM_PER_REQUEST}",
              }],
            }
          end

          check_run_data = {}
          head_sha = inputs[:head_sha]
          find_commit!(repo, head_sha)
          check_suite = inputs[:check_suite] || fetch_check_suite(head_sha: head_sha, repo: repo)

          if check_suite.actions_app? && inputs[:external_id].present?
            # reads from replicas so there is less impact if primaries are having an incident, see https://github.com/github/availability/issues/3103 and https://github.com/github/actions-sudo/issues/556
            ActiveRecord::Base.connected_to(role: :reading) do
              # transient errors can occur when launch creates check runs which may result in duplicate check runs so check for existing check runs using external_id, see https://github.com/github/actions-results-team/issues/1258
              existing_run = Checks.domain.check_runs.last_for_check_suite(check_suite: check_suite, repository_id: repo.id, name: inputs[:name], external_id: inputs[:external_id])
              if existing_run
                same_execution = check_suite&.workflow_run&.latest_workflow_run_execution&.id == existing_run.workflow_job_run&.workflow_run_execution_id
                if same_execution
                  GitHub.logger.info("duplicate create request for check run", {
                    "gh.check_run.id" => existing_run.id,
                    "gh.check_suite.id" => check_suite.id,
                  })
                  GitHub.dogstats.increment("checks.create_check_run.actions.already_exists")
                  return { check_run: existing_run, errors: [] }
                end
              end
            end
          end

          if check_suite.head_sha != head_sha || check_suite.repository != repo
            raise Platform::Errors::Unprocessable.new("The Check Suite does not match the SHA and Repository provided")
          end

          if inputs[:conclusion] == "stale"
            raise Platform::Errors::Validation.new("You cannot set a check run with `conclusion: stale`. `stale` is for internal use only.")
          end

          if (inputs[:status] == "waiting" || inputs[:status] == "pending") && !Platform::Helpers::ViaActions.using_internal_schema?(context)
            raise Platform::Errors::Validation.new("You cannot set a check run with `status: waiting` or `status: pending`. `waiting` and `pending` are for internal use only.")
          end

          check_run_data[:check_suite_id] = check_suite.id

          check_run_data[:started_at] = (inputs[:started_at] || Time.now)

          check_run_data[:status] = inputs[:status]
          check_run_data[:conclusion] = inputs[:conclusion]
          check_run_data[:status] = "completed" if inputs[:conclusion]

          check_run_data[:details_url] = inputs[:details_url].to_s if inputs[:details_url].present?
          check_run_data[:completed_at] = inputs[:completed_at]
          check_run_data[:external_id] = inputs[:external_id]
          check_run_data[:name] = inputs[:name]
          check_run_data[:display_name] = inputs[:display_name]

          image_data = []
          annotation_data = T.let([], T::Array[Platform::Objects::CheckAnnotation])
          if inputs[:output].present?
            inputs[:output].each do |output_key, output_value|
              if output_key == :images
                next unless inputs[:output][:images]
                inputs[:output][:images].each do |image_hash|
                  image_hash = image_hash.to_h
                  # need to force conversion from `Addressable::URI`
                  image_hash[:image_url] = image_hash[:image_url].to_s
                  image_data << image_hash.to_h
                end
              elsif output_key == :annotations
                next unless inputs[:output][:annotations]
                annotation_data = inputs[:output][:annotations].map do |annotation|
                  annotation_attrs = Inputs::CheckAnnotationData.hash_from_input(annotation)
                  annotation_attrs.merge({ repository: repo })

                end
              else
                check_run_data[output_key] = output_value
              end
            end
          end

          if inputs[:concurrency].present?
            unless Platform::Helpers::ViaActions.using_internal_schema?(context)
              raise Platform::Errors::Validation.new("You cannot set a check run with `concurrency`. `concurrency` is for internal use only.")
            end
            concurrency_hash = inputs[:concurrency].to_h
            waiting_on_resource = concurrency_hash[:waiting_on_resource]
            if waiting_on_resource.present?
              waiting_on_resource[:check_run_id] = id_from_global_id(waiting_on_resource[:check_run_id])
              waiting_on_resource[:check_suite_id] = id_from_global_id(waiting_on_resource[:check_suite_id])
            end

            check_run_data[:concurrency] = JSON.generate(concurrency_hash)
          end

          truncator = CheckRun::Truncator.new(check_run_data[:text])
          check_run_data[:text] = truncator.truncate
          check_run_data[:repository] = repo

          check_run = CheckRun.new(check_run_data)
          check_run.images = image_data
          check_run.annotations.build(annotation_data)

          actions = inputs[:actions]&.map do |action|
            CheckRunAction.new(action[:label], action[:identifier], action[:description])
          end

          check_run.actions = (actions || [])

          if inputs[:steps] && !check_run.disable_dotcom_check_steps_writes?
            inputs[:steps].each do |input_step|
              input_step_attributes = input_step.to_h

              if completed_log = input_step_attributes[:completed_log]
                input_step_attributes[:completed_log_url] = completed_log[:url]
                input_step_attributes[:completed_log_lines] = completed_log[:lines]
                input_step_attributes.except!(:completed_log)
              end

              check_run.steps.build(input_step_attributes)
            end
          end

          cloned = inputs.fetch(:is_cloned_from_previous_run, false)

          if cloned
            # For partial reruns, use the log values from the previous runs for successful (cloned) steps
            # ADR: https://github.com/github/c2c-actions/blob/main/docs/adrs/3797-logs-and-artifacts-for-partial-reruns.md
            key = inputs[:job_key]

            # forcing index because on some occasions the query planner chooses the wrong index resulting in slow or killed queries
            # See https://github.com/github/mysql-database-usage/issues/1841
            previous_workflow_job_run = Actions::WorkflowJobRun
              .from("workflow_job_runs FORCE INDEX(idx_repo_id_workflow_run_id_workflow_run_execution_id_job_key)")
              .where(repository_id: repo.id, workflow_run_id: check_suite.workflow_run.id, job_key: key)
              .last

            if previous_workflow_job_run
              if previous_workflow_job_run.check_run.present?
                check_run.completed_log_url   = T.must(previous_workflow_job_run.check_run).completed_log_url
                check_run.completed_log_lines = T.must(previous_workflow_job_run.check_run).completed_log_lines
              end

              check_run.summary_url = previous_workflow_job_run.summary_url if previous_workflow_job_run.summary_url.present?
            end
          else
            if inputs[:completed_log].present?
              check_run.completed_log_url   = inputs[:completed_log][:url].to_s
              check_run.completed_log_lines = inputs[:completed_log][:lines]
            end
            check_run.summary_url = inputs[:job_summary][:url].to_s if inputs.dig(:job_summary, :url).present?
          end

          check_run.number = inputs[:number] if inputs[:number].present?
          check_run.streaming_log_url = inputs[:streaming_log][:url] if inputs[:streaming_log]

          # Transient fields that will be assigned to the workflow job after the check run is created
          check_run.job_key                     = inputs[:job_key] if inputs[:job_key].present?
          check_run.parent_job_id               = inputs[:parent_job_id] if inputs[:parent_job_id].present?
          check_run.labels                      = inputs[:labels] if inputs[:labels].present?
          check_run.runner_id                   = inputs[:runner_id] if inputs[:runner_id].present?
          check_run.runner_group_id             = inputs[:runner_group_id] if inputs[:runner_group_id].present?
          check_run.runner_name                 = inputs[:runner_name] if inputs[:runner_name].present?
          check_run.runner_group_name           = inputs[:runner_group_name] if inputs[:runner_group_name].present?
          check_run.is_cloned_from_previous_run = inputs[:is_cloned_from_previous_run] if inputs[:is_cloned_from_previous_run].present?

          if check_run.save
            if truncator.truncated?
              truncator.report_silent_truncation!(
                check_run: check_run,
                repo: repo,
                integration: context[:integration],
                type: "an existing",
              )
            end
            MergeQueues.execute_from_sha!(repo, check_run.head_sha)
            begin
              check_run.create_deployment(inputs[:environment], is_cloned: cloned) if inputs[:environment].present? && can_create_deployment?(context[:permission], repo)
            rescue ActiveRecord::RecordInvalid
              check_run.annotations.create!(
                message: "Unable to create environment with name \"#{inputs[:environment]}\"",
                path: ".github",
                warning_level: "failure",
                start_line: 1,
                repository: check_run.repository,
                end_line: 1)
            end
            { check_run: check_run, errors: [] }
          else
            if truncator.truncated?
              truncator.report_silent_truncation!(
                check_run: check_run,
                repo: repo,
                integration: context[:integration],
                type: "an existing",
              )
            end
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(check_run, execution_errors)
            check_run_translate_hash = {
              summary: %w[output summary],
              annotations: %w[output annotations],
            }
            check_run_action_path_prefix = %w[input actions]
            { check_run: nil, errors: Platform::UserErrors.mutation_errors_for_model(check_run, translate: check_run_translate_hash) + Platform::UserErrors.mutation_errors_for_models(check_run.actions, path_prefix: check_run_action_path_prefix) }
          end
        end
      end

      private

      def id_from_global_id(global_id)
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] if global_id.present?
      end

      def fetch_check_suite(head_sha:, repo:)
        check_suite = find_check_suite(repo, head_sha, context[:integration])
        return check_suite if check_suite.present?

        check_suite = create_check_suite(repo, head_sha, context[:integration])
        return check_suite if check_suite.valid?

        raise Platform::Errors::Unprocessable.new(check_suite.errors.full_messages.join(", "))
      end

      def find_check_suite(repo, head_sha, integration)
        attributes = { head_sha: head_sha, github_app_id: integration.id }
        repo.check_suites.find_by(attributes)
      end

      def create_check_suite(repo, head_sha, integration)
        attributes = { head_sha: head_sha, github_app_id: integration.id }
        push = Repositories.domain.pushes.by_repo_id_and_after(after: head_sha, repository_id: repo.id)

        attributes = attributes.merge(push_id: push&.id)
        repo.check_suites.create(attributes)
      end
    end
  end
end
