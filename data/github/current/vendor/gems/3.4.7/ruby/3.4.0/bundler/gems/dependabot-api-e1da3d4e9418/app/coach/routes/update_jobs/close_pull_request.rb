# frozen_string_literal: true

require "dependabot/dependency"
require "dependabot/dependency_file"

require "renderer"

module Routes
  module UpdateJobs
    class ClosePullRequest < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.dependency-names" => { type: Array, required: true },
           "data.reason" => { type: String, required: true }

      requires :update_job

      def call
        return wrong_dependency_updated_error if wrong_dependency_updated

        update_job.increment_metric("close_pull_request.initiated")

        ClosePullRequestJob.perform_later(
          pull_request: pull_request,
          reason: params[:data][:reason],
        )

        Renderer.no_content
      end

      private

      def wrong_dependency_updated
        Set.new(update_job.dependencies) !=
          Set.new(params[:data][:"dependency-names"])
      end

      def wrong_dependency_updated_error
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Updated dependency was not in the list of dependencies " \
                  "requested for this update job",
        )
      end

      def pull_request
        @pull_request ||= update_job.pull_request_transition.pull_request
      end
    end
  end
end
