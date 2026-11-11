# frozen_string_literal: true

module SuggestedFixesService
  module V1
    class Handler
      # It doesn't look like google-protobuf makes the list of fields on a type
      # available as part of it's ruby api.  Workaround that limitation by storing
      # the keys from an empty DependencyMetadata message hash when the module is loaded.
      DEPENDENCY_METADATA_FIELDS = DependabotApi::V1::DependencyMetadata.new.to_h.keys.map(&:to_s).freeze

      class Error < StandardError
        attr_reader :twirp_error

        def initialize(msg, twirp_error)
          super(msg)
          @twirp_error = twirp_error
        end
      end

      def get_suggested_fix(req, env)
        suggested_fix = find_suggested_fix(req)

        suggested_fix.autofix_suggestion_job.observe_stage(stage: AutofixSuggestionJob::Stages::VIEW_ANNOTATION) do
          { suggested_fix: suggested_fix_hash(suggested_fix) }
        end
      rescue Error => e
        AutofixSuggestionJob::Stages.record_error(
          stage: AutofixSuggestionJob::Stages::VIEW_ANNOTATION,
          error: e,
          "gh.dependabot_api.autofix_suggestion_job.id": req.autofix_job_id,
        )
        log_error(req, env, e)
        e.twirp_error
      end

      def apply_suggested_fix(req, env)
        suggested_fix = find_suggested_fix(req)
        suggested_fix.autofix_suggestion_job.observe_stage(stage: AutofixSuggestionJob::Stages::APPROVE_FIX) do
          suggested_fix.review_status_approved!

          { success: true }
        end
      rescue Error => e
        AutofixSuggestionJob::Stages.record_error(
          stage: AutofixSuggestionJob::Stages::APPROVE_FIX,
          error: e,
          "gh.dependabot_api.autofix_suggestion_job.id": req.autofix_job_id,
        )
        log_error(req, env, e)
        e.twirp_error
      end

      def dismiss_suggested_fix(req, env)
        suggested_fix = find_suggested_fix(req)
        suggested_fix.autofix_suggestion_job.observe_stage(stage: AutofixSuggestionJob::Stages::DISMISS_FIX) do
          suggested_fix.review_status_dismissed!

          { success: true }
        end
      rescue Error => e
        AutofixSuggestionJob::Stages.record_error(
          stage: AutofixSuggestionJob::Stages::DISMISS_FIX,
          error: e,
          "gh.dependabot_api.autofix_suggestion_job.id": req.autofix_job_id,
        )
        log_error(req, env, e)
        e.twirp_error
      end

      private

      def log_error(req, env, error)
        Dependabot::Logger.info(
          msg: error.message,
          "code.namespace": "SuggestedFixesService::V1::Handler",
          "rpc.method": env[:rpc_method],
          "autofix_job_id": req.autofix_job_id,
        )
      end

      def validate_suggested_fix_request!(req)
        if req.autofix_job_id.zero?
          raise Error.new("autofix_job_id is not provided",
                          Twirp::Error.invalid_argument("autofix_job_id is required"))
        end

        if req.github_repo_id.zero?
          raise Error.new("github_repo_id is not provided",
                          Twirp::Error.invalid_argument("github_repo_id is required"))
        end

        return unless req.github_pull_request_number.zero?

        raise Error.new("github_pull_request_number is not provided",
                        Twirp::Error.invalid_argument("github_pull_request_number is required"))
      end

      def find_autofix_job(req)
        validate_suggested_fix_request!(req)

        job = AutofixSuggestionJob.includes(suggested_fix: :suggested_fix_files, pull_request: :repo).find_by!(
          id: req.autofix_job_id,
          pull_request: { github_number: req.github_pull_request_number },
          repo: { github_id: req.github_repo_id },
        )

        Dependabot::Exceptions.push(job.telemetry_attributes)
        job
      rescue ActiveRecord::RecordNotFound
        raise Error.new("AutofixSuggestionJob not found",
                        Twirp::Error.not_found("AutofixSuggestionJob ##{req.autofix_job_id} was not found"))
      end

      def find_suggested_fix(req)
        autofix_job = find_autofix_job(req)

        suggested_fix = autofix_job.suggested_fix
        if suggested_fix.nil?
          raise Error.new("SuggestedFix not found",
                          Twirp::Error.not_found("SuggestedFix for job #{autofix_job.id} was not found"))
        end

        suggested_fix
      end

      def suggested_fix_hash(suggested_fix)
        {
          id: suggested_fix.id,
          autofix_job_id: suggested_fix.autofix_suggestion_job_id,
          description: suggested_fix.description,
          files: suggested_fix_files_array(suggested_fix.suggested_fix_files),
          review_status: suggested_fix.review_status_before_type_cast,
          created_at: Google::Protobuf::Timestamp.new(
            seconds: suggested_fix.created_at.utc.to_i
          ),
          updated_at: Google::Protobuf::Timestamp.new(
            seconds: suggested_fix.updated_at.utc.to_i
          ),
          dependency_metadata: dependency_metadata_array(suggested_fix.dependency_metadata),
        }
      end

      def suggested_fix_files_array(suggested_fix_files)
        suggested_fix_files.map do |file|
          {
            file_path: file.file_path,
            diff_content: file.diff_content,
            created_at: Google::Protobuf::Timestamp.new(
              seconds: file.created_at.utc.to_i
            ),
            updated_at: Google::Protobuf::Timestamp.new(
              seconds: file.updated_at.utc.to_i
            ),
          }
        end
      end

      def dependency_metadata_array(metadata)
        return [] if metadata.blank?

        parsed_metadata = JSON.parse(metadata)
        Array(parsed_metadata).map { |m| m.slice(*DEPENDENCY_METADATA_FIELDS) }
      rescue JSON::ParserError => e
        raise Error.new("Failed to parse dependency metadata JSON", Twirp::Error.internal(e.message))
      end
    end
  end
end
