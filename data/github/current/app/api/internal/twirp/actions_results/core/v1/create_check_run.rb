# typed: true
# frozen_string_literal: true

require "scientist"

module Api::Internal::Twirp::ActionsResults
  module Core
    module V1
      class CreateCheckRun
        include Scientist

        MAX_RERUN_WATERMARK = T.let(10, Integer)

        attr_reader :req, :env

        def self.call(request, env)
          new(request, env).call
        end

        def initialize(request, env)
          @req = request
          @env = env
        end

        def call
          return Twirp::Error.not_found("repository does not exist", argument: "repository_id") unless repository
          return Twirp::Error.not_found("check suite does not exist", argument: "check_suite_id") unless check_suite

          duplicate_request = T.let(false, T::Boolean)
          existing_run = T.let(nil, T.nilable(CheckRun))

          if FeatureFlag.vexi.enabled?(:actions_avoid_dup_check_run_large_rerun_new_logic, repository, default: false)
            latest_workflow_run_execution = check_suite.workflow_run&.latest_workflow_run_execution

            # if there are many rerun attempts, check if the request is a duplicate
            # by checking if the external_id is already present in the latest workflow run execution
            # this is to avoid creating multiple check runs for the same job_id in case of many reruns
            if (latest_workflow_run_execution&.attempt || 0) > MAX_RERUN_WATERMARK
              all_check_runs = latest_workflow_run_execution&.workflow_job_runs&.includes(:check_run).map(&:check_run)
              existing_run = all_check_runs.find { |run| run.external_id == req.job_id }
              duplicate_request = existing_run.present?
            else
              existing_run = Checks.domain.check_runs.last_for_check_suite(check_suite: check_suite, repository_id: repository.id, external_id: req.job_id)
              same_execution = latest_workflow_run_execution&.id == existing_run&.workflow_job_run&.workflow_run_execution_id
              duplicate_request = !!(existing_run.present? && same_execution)
            end
          else
            existing_run = Checks.domain.check_runs.last_for_check_suite(check_suite: check_suite, repository_id: repository.id, external_id: req.job_id)
            same_execution = check_suite&.workflow_run&.latest_workflow_run_execution&.id == existing_run&.workflow_job_run&.workflow_run_execution_id
            duplicate_request = !!(existing_run.present? && same_execution)
          end

          if duplicate_request
            GitHub.logger.info("duplicate create request for check run", {
              "gh.check_run.id" => existing_run&.id,
              "gh.check_suite.id" => check_suite.id,
            })
            GitHub.dogstats.increment("checks.create_check_run.actions.already_exists")
            return {
              check_run_id: existing_run&.id
            }
          end

          check_run = CheckRun.new(
            repository_id: repository.id,
            check_suite_id: check_suite.id,
            external_id: req.job_id,
            status: ActionsResults::Utils.to_monolith_status(req.status),
            conclusion: ActionsResults::Utils.to_monolith_conclusion(req.conclusion),
            started_at: req.started_at&.to_time,
            completed_at: req.completed_at&.to_time,
            name: req.job_id, # the name attribute is always the external_id/backend_id/job_id
            display_name: req.display_name,
            number: req.job_order_number
          )

          # transient fields that will be assigned to workflow job run
          check_run.labels = req.labels if req.labels.present?
          check_run.runner_id = req.runner_id if req.runner_id&.nonzero?
          check_run.runner_name = req.runner_name if req.runner_name.present?
          check_run.runner_group_id = req.runner_group_id if req.runner_group_id&.nonzero?
          check_run.runner_group_name = req.runner_group_name if req.runner_group_name.present?

          # known missing attributes:
          # - product_sku
          check_run.job_key = req.job_key if req.job_key.present?
          check_run.parent_job_id = req.parent_job_id if req.parent_job_id.present?
          if req.is_cloned_from_previous_run
            # forcing index because on some occasions the query planner chooses the wrong index resulting in slow or killed queries, see https://github.com/github/mysql-database-usage/issues/1841
            previous_workflow_job_run = Actions::WorkflowJobRun
              .from("workflow_job_runs FORCE INDEX(idx_repo_id_workflow_run_id_workflow_run_execution_id_job_key)")
              .where(repository_id: repository.id, workflow_run_id: check_suite.workflow_run.id, job_key: req.job_key)
              .last

            if previous_workflow_job_run
              if previous_workflow_job_run.check_run.present?
                check_run.completed_log_url   =  T.must(previous_workflow_job_run.check_run).completed_log_url
                check_run.completed_log_lines =  T.must(previous_workflow_job_run.check_run).completed_log_lines
              end
              check_run.summary_url = previous_workflow_job_run.summary_url if previous_workflow_job_run.summary_url.present?
            end
          end
          if req.concurrency.present?
            concurrency = { group: req.concurrency.group }
            if req.concurrency.waiting_on_resource.present?
              concurrency[:waiting_on_resource] = { check_run_id: id_from_global_id(req.concurrency.waiting_on_resource.check_run_global_id), check_suite_id: id_from_global_id(req.concurrency.waiting_on_resource.check_suite_global_id) }
            end

            check_run.concurrency = JSON.generate(concurrency)
          end

          check_run.annotations.build(annotations)
          if !check_run.disable_dotcom_check_steps_writes?
            check_run.steps.build(steps)
          end

          check_run.save!

          begin
            if req&.environment&.name.present?
              check_run.create_deployment(req.environment.name, is_cloned: req.is_cloned_from_previous_run)
            end
          rescue ActiveRecord::RecordInvalid
            check_run.annotations.create!(
              message: "Unable to create environment with name \"#{req.environment.name}\"",
              path: ".github",
              warning_level: "failure",
              start_line: 1,
              repository: check_run.repository,
              end_line: 1
            )
          end

          MergeQueues.execute_from_sha!(repository, check_run.head_sha)

          {
            check_run_id: check_run.id
          }
        end

        private

        def annotations
          return [] unless req.annotations

          req.annotations.map do |annotation|
            {
              # required attributes
              filename: annotation.path&.value || ".github",
              warning_level: to_annotation_level(annotation.level),
              message: annotation.message,
              start_line: annotation.start_line&.value || 1,
              end_line: annotation.end_line&.value || 1,
              check_suite_id: req.check_suite_id,
              repository_id: req.repository_id,
              # optional attributes
              raw_details: annotation.raw_details&.value,
              title: annotation.title&.value,
              start_column: annotation.start_column&.value,
              end_column: annotation.end_column&.value,
              step_number: annotation.step_number&.value,
            }.compact
          end
        end

        def steps
          return [] unless req.steps

          req.steps.map do |step|
            {
              number: step.number,
              conclusion: ActionsResults::Utils.to_monolith_conclusion(step.conclusion),
              name: step.name,
              completed_log_url: step.completed_log_url&.value,
              completed_log_lines: step.completed_log_lines&.value,
              started_at: step.started_at&.to_time,
              completed_at: step.completed_at&.to_time,
              status: ActionsResults::Utils.to_monolith_status(step.status),
              external_id: step.external_id,
              repository_id: req.repository_id,
            }.compact
          end
        end

        def to_annotation_level(level)
          case level
          when :ANNOTATION_LEVEL_INVALID
            nil
          when :ANNOTATION_LEVEL_NOTICE
            :notice
          when :ANNOTATION_LEVEL_WARNING
            :warning
          when :ANNOTATION_LEVEL_FAILURE
            :failure
          end
        end

        def check_suite
          @check_suite ||= CheckSuite.find_by(repository_id: repository.id, id: req.check_suite_id)
        end

        def repository
          @repository ||= Repositories.domain.by_id(req.repository_id)
        end

        def id_from_global_id(global_id)
          Platform::Helpers::NodeIdentification.from_global_id(global_id)[1] if global_id.present?
        end
      end
    end
  end
end
