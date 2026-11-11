# frozen_string_literal: true

require "renderer"
require "json"

module Routes
  module UpdateJobs
    class MarkAsProcessed < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.base-commit-sha" => { type: String, required: true }

      requires :update_job

      BASE_COMMIT_SHA_MAX_LENGTH = 40

      # rubocop:disable Metrics/MethodLength
      # rubocop:disable Metrics/AbcSize
      def call
        base_commit_sha = params[:data][:"base-commit-sha"]
        return wrong_base_commit_sha_error if base_commit_sha.length > BASE_COMMIT_SHA_MAX_LENGTH

        # If the update job timed out, the runner sends "unknown" which will break
        # any PR creation that happens after the timeout. So ignore this value
        # if we already have one from the create_pull_request endpoint.
        update_job.update!(base_commit_sha: base_commit_sha) if update_job.base_commit_sha.blank?

        duration = Time.now.in_time_zone - update_job.created_at
        update_job.timing_metric("mark_as_processed.duration",
                                 duration,
                                 tags: {
                                   lt_20m: duration < 20.minutes,
                                 })

        if timed_out?
          HandleUpdaterTimeout.new(
            update_job: update_job,
            event_source: "api.mark_as_processed"
          ).run
        elsif failure?
          retried = HandleUpdaterFailure.retry(update_job)

          # TODO: Deprecate error_type in favor of error_category as error_type
          # is already used by `job.error.created` remove by 2020-10-31
          update_job.increment_metric(
            "mark_as_processed.errored",
            tags: {
              retry: retried,
              error_type: update_job.job_metric_error_category,
              error_category: update_job.job_metric_error_category,
              config_file: update_job.update_config.using_config_file?,
            }
          )
        else
          update_job.transition_to!(:processed)
          enqueue_rate_limit_review if update_config.in_state?(:rate_limited)

          update_job.increment_metric(
            "mark_as_processed.completed",
            tags: {
              config_file: update_job.update_config.using_config_file?,
            }
          )

          handle_update_jobs_for_multiple_ecosystems
        end

        Renderer.no_content
      end
      # rubocop:enable Metrics/MethodLength
      # rubocop:enable Metrics/AbcSize

      private

      def multi_ecosystems_enabled?
        update_job.config_feature_enabled?(:multi_ecosystems)
      end

      def handle_update_jobs_for_multiple_ecosystems
        return unless multi_ecosystems_enabled?
        return unless multi_ecosystem_sibling_jobs_present?

        CombinePullRequestsAfterJobsCompletion.perform_later(associated_update_job_ids: multi_ecosystem_sibling_job_ids)
      end

      def multi_ecosystem_sibling_jobs_present?
        multi_ecosystem_sibling_job_ids.present?
      end

      def multi_ecosystem_sibling_job_ids
        @multi_ecosystem_sibling_job_ids ||= update_job.multi_ecosystem_siblings_enqueued_together.ids
      end

      def timed_out?
        update_job.unique_errors.any? { |e| e.error_type == "timed_out" }
      end

      def failure?
        return true if update_job.unique_errors.any?
        return false unless creating_a_security_update?
        return false unless update_job.no_potential_pull_requests?

        true
      end

      def creating_a_security_update?
        update_job.github_request? && !update_job.updating_a_pull_request?
      end

      def update_config
        @update_config ||= update_job.update_config
      end

      def enqueue_rate_limit_review
        ReviewUpdateConfigRateLimit.
          set(wait: 30.minutes).
          perform_later(update_job: update_job)
      end

      def wrong_base_commit_sha_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "base commit sha length is greater then 40 characters",
        )
      end
    end
  end
end
