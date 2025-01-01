# typed: true
# frozen_string_literal: true

require "monolith-twirp-dependency_graph_platform-actions"

module Api::Internal::Twirp::DependencyGraphPlatform
  module Actions
    module V1
      class ActionsAPIHandler < Api::Internal::Twirp::Handler
        Proto = Github::DependencyGraphPlatform::GhInternal::Actions::V1

        allow_access_for :client, allowed_clients: ["dependency_graph_platform"]
        handles_service Proto::ActionsAPIService

        sig do
          params(
            req: Proto::GetWorkflowRunRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::GetWorkflowRunResponse,
              Twirp::Error
            )
          )
        end
        def get_workflow_run(req, env)
          unless req.workflow_run_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "workflow_run_id")
          end

          workflow_run = ::Actions::WorkflowRun.find_by(id: req.workflow_run_id)

          unless workflow_run.present?
            return Twirp::Error.not_found("failed to fetch", argument: "workflow_run_id")
          end

          unless workflow_run.workflow_file_path.starts_with?("dynamic/dependency-graph/")
            return Twirp::Error.internal("workflow must be a dependency graph workflow")
          end

          Proto::GetWorkflowRunResponse.new(
            workflow_run: proto_workflow_run(workflow_run)
          )
        end

        sig do
          params(
            req: Proto::GetCheckRunAnnotationsRequest,
            env: T::Hash[String, T.untyped]
          ).returns(
            T.any(
              Proto::GetCheckRunAnnotationsResponse,
              Twirp::Error
            )
          )
        end
        def get_check_run_annotations(req, env)
          unless req.check_run_id.present?
            return Twirp::Error.invalid_argument("must be non-empty", argument: "check_run_id")
          end

          check_run = ::CheckRun.find_by(id: req.check_run_id)

          unless check_run.present?
            return Twirp::Error.not_found("failed to fetch", argument: "check_run_id")
          end

          unless check_run.check_suite&.workflow_run&.workflow_file_path.starts_with?("dynamic/dependency-graph/")
            return Twirp::Error.internal("workflow must be a dependency graph workflow")
          end


          Proto::GetCheckRunAnnotationsResponse.new(
            annotations: check_run.annotations.map do |annotation|
              Proto::CheckAnnotation.new(
                level: proto_check_annotation_level(annotation.annotation_level),
                message: annotation.message
              )
            end
          )
        end

        private

        sig do
          params(annotation_level: T.nilable(String)).returns(Integer)
        end
        def proto_check_annotation_level(annotation_level)
          case annotation_level
          when "notice"
            Proto::CheckAnnotationLevel::CHECK_ANNOTATION_LEVEL_NOTICE
          when "warning"
            Proto::CheckAnnotationLevel::CHECK_ANNOTATION_LEVEL_WARNING
          when "failure"
            Proto::CheckAnnotationLevel::CHECK_ANNOTATION_LEVEL_FAILURE
          else
            Proto::CheckAnnotationLevel::CHECK_ANNOTATION_LEVEL_INVALID
          end
        end

        sig do
          params(workflow_run: ::Actions::WorkflowRun).returns(Proto::WorkflowRun)
        end
        def proto_workflow_run(workflow_run)
          Proto::WorkflowRun.new(
            id: workflow_run.id,
            name: workflow_run.name,
            workflow_file_path: workflow_run.workflow_file_path,
            check_runs: workflow_run.jobs.map do |check_run|
              proto_check_run(T.let(check_run, ::CheckRun))
            end
          )
        end

        sig do
          params(check_run: ::CheckRun).returns(Proto::CheckRun)
        end
        def proto_check_run(check_run)
          check_steps = if check_run.passthrough_steps?
            check_run.steps_from_backend
          else
            check_run.steps
          end
          Proto::CheckRun.new(
            id: check_run.id,
            status: proto_check_run_status(check_run.status),
            conclusion: proto_check_run_conclusion(check_run.conclusion),
            details_url: check_run.details_url,
            started_at: proto_timestamp(check_run.started_at),
            completed_at: proto_timestamp(check_run.completed_at),
            display_name: check_run.display_name,
            steps: check_steps.map do |check_step|
              check_step = T.let(check_step, ::CheckStep)
              proto_check_step(check_step)
            end
          )
        end

        sig do
          params(check_step: ::CheckStep).returns(Proto::CheckStep)
        end
        def proto_check_step(check_step)
          Proto::CheckStep.new(
            id: check_step.id,
            conclusion: proto_check_run_conclusion(check_step.conclusion),
            name: check_step.name,
            started_at: proto_timestamp(check_step.started_at),
            completed_at: proto_timestamp(check_step.completed_at),
            status: proto_check_run_status(check_step.status)
          )
        end

        sig do
          params(status: T.nilable(String)).returns(Integer)
        end
        def proto_check_run_status(status)
          case status
          when "requested"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_REQUESTED
          when "queued"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_QUEUED
          when "in_progress"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_IN_PROGRESS
          when "completed"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_COMPLETED
          when "waiting"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_WAITING
          when "pending"
            Proto::CheckRunStatus::CHECK_RUN_STATUS_PENDING
          else
            Proto::CheckRunStatus::CHECK_RUN_STATUS_INVALID
          end
        end

        sig do
          params(conclusion: T.nilable(String)).returns(Integer)
        end
        def proto_check_run_conclusion(conclusion)
          case conclusion
          when "neutral"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_NEUTRAL
          when "success"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_SUCCESS
          when "failure"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_FAILURE
          when "cancelled"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_CANCELLED
          when "action_required"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_ACTION_REQUIRED
          when "timed_out"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_TIMED_OUT
          when "skipped"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_SKIPPED
          when "stale"
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_STALE
          else
            Proto::CheckRunConclusion::CHECK_RUN_CONCLUSION_INVALID
          end
        end

        sig do
          params(time: T.nilable(ActiveSupport::TimeWithZone)).returns(Google::Protobuf::Timestamp)
        end
        def proto_timestamp(time)
          Google::Protobuf::Timestamp.new(seconds: time.to_i)
        end
      end
    end
  end
end
