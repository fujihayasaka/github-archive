# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateCheckRun < Platform::Mutations::Base
      include Platform::Helpers::GitHubAppValidation

      description "Update a check run"

      minimum_accepted_scopes ["public_repo"]

      limit_actors_to [:github_app]

      argument :repository_id, ID, "The node ID of the repository.", required: true, loads: Objects::Repository, as: :repo
      argument :check_run_id, ID, "The node of the check.", required: true, loads: Objects::CheckRun

      argument :name, String, "The name of the check.", required: false
      argument :display_name, String, "Optional name that, if defined, will be used in the UI instead of the name.", required: false, visibility: :internal
      argument :details_url, Scalars::URI, "The URL of the integrator's site that has the full details of the check.", required: false
      argument :external_id, String, "A reference for the run on the integrator's system.", required: false
      argument :status, Enums::RequestableCheckStatusState, "The current status.", required: false
      argument :started_at, Scalars::DateTime, "The time that the check run began.", required: false
      argument :conclusion, Enums::CheckConclusionState, "The final conclusion of the check.", required: false
      argument :completed_at, Scalars::DateTime, "The time that the check run finished.", required: false
      argument :output, Inputs::CheckRunOutput, "Descriptive details about the run.", required: false
      argument :actions, [Inputs::CheckRunAction], "Possible further actions the integrator can perform, which a user may trigger.", required: false
      argument :steps, [Inputs::CheckStepData], "Steps information to be updated", visibility: :internal, required: false
      argument :streaming_log, Inputs::StreamingLogData, "Streaming log information", visibility: :internal, required: false
      argument :completed_log, Inputs::CompletedLogData, "The completed log information", visibility: :internal, required: false
      argument :job_summary, Inputs::JobSummaryData, "Summary data for workflow job",  visibility: :internal, required: false
      argument :number, Int, "The topological order of the check run within the check suite.", visibility: :internal, required: false
      argument :environment, String, "Deployment environment for Actions CD", visibility: :internal, required: false
      argument :environment_url, String, "Deployment URL for Actions CD", visibility: :internal, required: false
      argument :job_key, String, "The job key.", visibility: :internal, required: false
      argument :parent_job_id, String, "The ID of the parent job.", visibility: :internal, required: false
      argument :labels, [String], "labels to be applied to this job as a json array", visibility: :internal, required: false
      argument :runner_id, Int, "The ID of the self-hosted runner, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_group_id, Int, "The ID of the self-hosted runner group, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_name, String, "The name of the self-hosted runner, if the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :runner_group_name, String, "The name of the self-hosted runner group, iff the workflow_job has been assigned to a runner", visibility: :internal, required: false
      argument :concurrency, Inputs::Concurrency, "The concurency information about the check run", visibility: :internal, required: false
      argument :is_cloned_from_previous_run, Boolean, "Indicates whether the run being updated was cloned from a previous run for a partial rerun", visibility: :internal, required: false

      error_fields

      field :check_run, Objects::CheckRun, "The updated check run.", null: true

      extras [:execution_errors]

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
        rescue Platform::Errors::NotFound
          false
        end
      end

      def resolve(check_run:, repo:, execution_errors:, **inputs)
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

        if repo.id != check_run.check_suite.repository_id # effectively, a 404
          raise Platform::Errors::NotFound.new("Could not resolve check run `#{check_run.global_relay_id}` to repository `#{repo.global_relay_id}`")
        end

        unless allowed_to_modify_app?(app_id: check_run.check_suite.github_app_id) # effectively, a 403
          raise Platform::Errors::Forbidden.new("GitHub App `#{context[:integration].id}` can't manage check suite `#{check_run.check_suite.global_relay_id}`")
        end

        if check_run.is_actions_check_run? && !Platform::Helpers::ViaActions.using_internal_schema?(context)
          GitHub.dogstats.increment("checks.actions_check_run_manually_updated")

          if inputs[:conclusion].present? || inputs[:status].present?
            GitHub.dogstats.increment("checks.actions_check_run_manually_updated_with_status_or_conclusion")
            GitHub.logger.info(
              "Actions check run was manually updated using GITHUB_TOKEN using the update check run API",
              "code.namespace" => self.class.name,
              "code.function" => __method__,
              "gh.repository.id" => repo.id,
              "gh.check_run.id" => check_run.id,
              "gh.check_run.status" => inputs[:status],
              "gh.check_run.conclusion" => inputs[:conclusion],
            )

            warning_enabled = repo.feature_enabled?(:checks_warning_annotation_restrict_update_check_run_with_github_token)
            failure_enabled = repo.feature_enabled?(:checks_restrict_update_check_run_with_github_token)

            if warning_enabled && !failure_enabled
              warning_annotation_data = {
                filename: ".github",
                warning_level: "warning",
                message: "The status or conclusion of this Actions created check run was updated using GITHUB_TOKEN. This will soon be restricted. For more information please see https://github.blog/changelog/2025-02-12-notice-of-upcoming-deprecations-and-breaking-changes-for-github-actions/#changes-to-check-run-status-modification.",
                start_line: 1,
                end_line: 1,
                repository_id: check_run.repository_id,
                check_run: check_run
              }

              CheckAnnotation.transaction do
                ca = CheckAnnotation.new warning_annotation_data
                ca.save
              end
            end

            if failure_enabled
              failure_annotation_data = {
                filename: ".github",
                warning_level: "failure",
                message: "The status or conclusion of this Actions created check run was attempted to be updated using GITHUB_TOKEN but was blocked. For more information please see https://github.blog/changelog/2025-02-12-notice-of-upcoming-deprecations-and-breaking-changes-for-github-actions/#changes-to-check-run-status-modification.",
                start_line: 1,
                end_line: 1,
                repository_id: check_run.repository_id,
                check_run: check_run
              }

              CheckAnnotation.transaction do
                ca = CheckAnnotation.new failure_annotation_data
                ca.save
              end

              raise Platform::Errors::Validation.new("Check run status and conclusions can only be updated internally by GitHub Actions. Please see https://github.blog/changelog/2025-02-12-notice-of-upcoming-deprecations-and-breaking-changes-for-github-actions/#changes-to-check-run-status-modification")
            end
          end
        end

        if inputs[:conclusion] == "stale"
          raise Platform::Errors::Validation.new("You cannot set a check run with `conclusion: stale`. `stale` is for internal use only.")
        end

        if (inputs[:status] == "waiting" || inputs[:status] == "pending") && !Platform::Helpers::ViaActions.using_internal_schema?(context)
          raise Platform::Errors::Validation.new("You cannot set a check run with `status: waiting` or `status: pending`. `waiting` and `pending` are for internal use only.")
        end

        check_run.name         = inputs[:name] if inputs[:name].present?
        check_run.details_url  = inputs[:details_url].to_s if inputs[:details_url].present?
        check_run.conclusion   = inputs[:conclusion] if inputs[:conclusion].present?
        check_run.started_at   = inputs[:started_at] if inputs[:started_at].present?
        check_run.completed_at = inputs[:completed_at] if inputs[:completed_at].present?
        check_run.external_id  = inputs[:external_id] if inputs[:external_id].present?
        check_run.display_name = inputs[:display_name] if inputs[:display_name].present?

        if inputs[:conclusion].present?
          check_run.status = "completed"
        elsif inputs[:status].present?
          check_run.status = inputs[:status]
        end

        image_data = []
        annotation_data = T.let([], T::Array[Platform::Objects::CheckAnnotation])
        if inputs[:output].present?
          inputs[:output].each do |output_key, output_value|
            if output_key == :images
              inputs[:output][:images].each do |image_hash|
                image_hash = image_hash.to_h
                # need to force conversion from `Addressable::URI`
                image_hash[:image_url] = image_hash[:image_url].to_s
                image_data << image_hash.to_h
              end
            elsif output_key == :annotations
              annotation_data = inputs[:output][:annotations].map do |annotation|
                annotation_attrs = Inputs::CheckAnnotationData.hash_from_input(annotation)
                annotation_attrs.merge({ repository: check_run.repository })
              end
            else
              check_run_data[output_key] = output_value
            end
          end
        end

        check_run.summary = check_run_data[:summary] if check_run_data[:summary].present?
        check_run.title   = check_run_data[:title] if check_run_data[:title].present?

        if check_run_data[:text].present?
          truncator = CheckRun::Truncator.new(check_run_data[:text])
          check_run.text = truncator.truncate
          if truncator.truncated?
            truncator.report_silent_truncation!(
              check_run: check_run,
              repo: repo,
              integration: context[:integration],
              type: "an existing",
            )
          end
        end

        check_run.images = image_data

        check_run.annotations.build(annotation_data)

        actions = inputs[:actions]&.map do |action|
          CheckRunAction.new(action[:label], action[:identifier], action[:description])
        end

        check_run.actions = (actions || [])

        cloned = inputs[:is_cloned_from_previous_run] if inputs[:is_cloned_from_previous_run].present?

        if inputs[:steps] && !check_run.disable_dotcom_check_steps_writes?
          steps = check_run.steps

          steps_hash = steps.index_by(&:external_id)
          previous_check_run = check_run.check_suite.check_runs.with_display_name(check_run.display_name).where.not(id: check_run.id).last if cloned
          previous_check_run_steps = previous_check_run.steps.index_by(&:external_id) if previous_check_run

          inputs[:steps].each do |input_step|
            check_step = steps_hash[input_step[:external_id]]
            check_step ||= check_run.steps.build(number: input_step[:external_id])

            if input_step[:completed_log].present?
              check_step.completed_log_url   = input_step[:completed_log][:url].to_s
              check_step.completed_log_lines = input_step[:completed_log][:lines]
            elsif cloned && previous_check_run_steps
              previous_step = previous_check_run_steps[input_step[:external_id]]
              if previous_step
                check_step.completed_log_url   = previous_step.completed_log_url
                check_step.completed_log_lines = previous_step.completed_log_lines
              end
            end

            check_step.name         = input_step[:name] if input_step[:name].present?
            check_step.completed_at = input_step[:completed_at] if input_step[:completed_at].present?
            check_step.started_at   = input_step[:started_at] if input_step[:started_at].present?
            check_step.status       = input_step[:status] if input_step[:status].present?
            check_step.conclusion   = input_step[:conclusion] if input_step[:conclusion].present?
            check_step.external_id  = input_step[:external_id] if input_step[:external_id].present?
            check_step.number       = input_step[:number] if input_step[:number].present?
          end
        end

        if inputs[:completed_log].present? && !cloned
          check_run.completed_log_url = inputs[:completed_log][:url].to_s
          check_run.completed_log_lines = inputs[:completed_log][:lines]
        end
        check_run.number = inputs[:number] if inputs[:number].present?
        check_run.streaming_log_url = inputs[:streaming_log][:url] if inputs[:streaming_log]

        if check_run.workflow_job_run
          check_run.workflow_job_run.job_key = inputs[:job_key] if inputs[:job_key].present?
          check_run.workflow_job_run.parent_job_id = inputs[:parent_job_id] if inputs[:parent_job_id].present?
          check_run.workflow_job_run.label_data = inputs[:labels] if inputs[:labels].present?
          check_run.workflow_job_run.runner_id = inputs[:runner_id] if inputs[:runner_id].present?
          check_run.workflow_job_run.runner_name = inputs[:runner_name] if inputs[:runner_name].present?
          check_run.workflow_job_run.runner_group_id = inputs[:runner_group_id] if inputs[:runner_group_id].present?
          check_run.workflow_job_run.runner_group_name = inputs[:runner_group_name] if inputs[:runner_group_name].present?
          if inputs[:job_summary].present?
            check_run.workflow_job_run.summary_url = inputs[:job_summary][:url].to_s if inputs[:job_summary][:url].present?
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
              check_run.workflow_job_run.concurrency = JSON.generate(concurrency_hash)
            end
          end

          check_run.workflow_job_run.save
        end

        begin
          if check_run.save
            MergeQueues.execute_from_sha!(repo, check_run.head_sha)

            # If we get an invalid environment, we should still pass back the updated check run which has already been saved
            # We might want to skip this step as well since it's unclear if we ever want to update the environment
            begin
              if can_create_deployment?(context[:permission], repo)
                check_run.create_deployment(inputs[:environment], is_cloned: cloned) if inputs[:environment].present?
                check_run.create_deployment_status(inputs[:environment_url]) if check_run.deployment.present?
              end
            rescue ActiveRecord::RecordInvalid
            end


            { check_run: check_run, errors: [] }
          else
            Platform::UserErrors.append_legacy_mutation_model_errors_to_context(check_run, execution_errors)
            check_run_translate_hash = { summary: %w[output summary] }
            check_run_action_path_prefix = %w[input actions]
            {
              check_run: nil,
              errors: (
                Platform::UserErrors.mutation_errors_for_model(check_run, translate: check_run_translate_hash) +
                Platform::UserErrors.mutation_errors_for_models(check_run.actions, path_prefix: check_run_action_path_prefix)
              )
            }
          end
        rescue ActiveRecord::RecordNotUnique => e
          message = "Record not unique."
          # Extract the specific case that we know of, where a race condition means a check step already exists with the same number
          if match = e.message.match(/Duplicate entry '\d*-(\d*)' for key 'index_check_steps_on_check_run_id_and_number'/)
            message = "Duplicate check step `#{match[1]}` already exists."
          end
          raise Platform::Errors::Unprocessable.new(message)
        end
      end

      def id_from_global_id(global_id)
        Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] if global_id.present?
      end
    end
  end
end
