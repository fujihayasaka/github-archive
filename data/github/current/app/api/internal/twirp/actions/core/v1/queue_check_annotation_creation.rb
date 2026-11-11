# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::Actions
  module Core
    module V1
      class QueueCheckAnnotationCreation
        WARNING_LEVEL_MAP = {
          ANNOTATION_WARNING_LEVEL_NOTICE: "notice",
          ANNOTATION_WARNING_LEVEL_WARNING: "warning",
          ANNOTATION_WARNING_LEVEL_FAILURE: "failure",
        }.freeze

        attr_reader :req

        def self.call(request)
          new(request).call
        end

        def initialize(request)
          @req = request
        end

        def call
          return Twirp::Error.invalid_argument("must be non-empty", argument: "repo_id") if req.repo_id.blank? || req.repo_id == 0
          return Twirp::Error.invalid_argument("must be non-empty", argument: "check_suite_id") if req.check_suite_id.blank? || req.check_suite_id == 0
          return Twirp::Error.invalid_argument("must be non-empty", argument: "job_id") if req.job_id.blank?
          return Twirp::Error.invalid_argument("must be non-empty", argument: "message") if req.message.blank?

          repository = Repository.find_by(id: req.repo_id)
          return Twirp::Error.not_found("repository does not exist", argument: "repo_id") unless repository

          check_suite = CheckSuite.find_by(id: req.check_suite_id, repository_id: repository.id)
          return Twirp::Error.not_found("check suite does not exist", argument: "check_suite_id") unless check_suite

          workflow_run = check_suite.workflow_run
          return Twirp::Error.not_found("workflow run does not exist", argument: "check_suite_id") unless workflow_run

          CreateActionsAnnotationsJob.perform_later(
            repo_id: repository.id,
            workflow_run_id: workflow_run.id,
            job_id: req.job_id,
            message: req.message,
            warning_level: resolve_warning_level,
          )

          { is_queued: true }
        end

        private

        def resolve_warning_level
          WARNING_LEVEL_MAP[req.warning_level] || "warning"
        end
      end
    end
  end
end
