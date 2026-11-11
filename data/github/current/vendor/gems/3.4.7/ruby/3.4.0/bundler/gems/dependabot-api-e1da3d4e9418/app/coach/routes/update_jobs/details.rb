# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class Details < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken

      requires :update_job

      def call
        return stale_job_error unless update_job.in_state?(:enqueued, :processing)

        mark_update_job_as_processing
        record_update_job_experiments

        Renderer.resource(
          update_job,
          serializer_options: { serializer: UpdateJobSerializerPrivate },
        )
      rescue UpdateConfigRegistry::RegistryNotFound
        UpdateJobError.create!(
          update_job: update_job,
          error_type: "runner_error",
          error_details: { "message": "Registry Not Found: UpdateConfig references a non-existent registry" }
        )
        Renderer.render_error(
          status: 422,
          title: "Registry Not Found",
          detail: "UpdateConfig references a non-existent registry",
        )
      end

      private

      def stale_job_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Update job has already been processed",
        )
      end

      def mark_update_job_as_processing
        Statesman::Machine.retry_conflicts(3) do
          next if update_job.in_state?(:processing)

          update_job.transition_to!(:processing)
        end

        update_job.increment_metric("update_job.processing")
      end

      def record_update_job_experiments
        experiments = update_job.reportable_experiments
        return if experiments.empty?

        update_job.metrics_metadata ||= {}
        update_job.metrics_metadata["experiments"] = experiments
        update_job.save!
      end
    end
  end
end
