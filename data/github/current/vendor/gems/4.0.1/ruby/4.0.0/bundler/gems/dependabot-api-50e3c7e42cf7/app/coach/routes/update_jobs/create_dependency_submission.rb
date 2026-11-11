# frozen_string_literal: true

require "renderer"
require "time"

# The CreateDependencySubmission endpoint relays a payload to DS-API, see:
#   https://github.com/github/dependency-snapshots-api
#
# The payload is expected to match the public REST API, see:
#   https://docs.github.com/en/rest/dependency-graph/dependency-submission
#
# The payload is transported as a protobuf via Twirp to a dedicated Dependabot
# service that handles it using 'incremental' snapshot logic that allows us to
# build up the current state of a branch in response to manifest changes.
#
# For internal documentation on Snapshots, refer to the service glossary:
#   https://github.com/github/dependency-snapshots-api/blob/main/docs/glossary.md
#
module Routes
  module UpdateJobs
    class CreateDependencySubmission < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams, "data" => { required: true }

      requires :update_job

      def call
        Dependabot::Logger.info(
          "code.namespace": "CreateDependencySubmission",
          **update_job.telemetry_attributes,
        )

        submit_snapshot
        Renderer.no_content
      rescue DependencyGraph::Snapshots::InvalidSnapshotError => e
        log_error(e)
        bad_request
      rescue DependencyGraph::Snapshots::Error, Octokit::Error, StandardError => e
        log_error(e)
        internal_server_error
      end

      private

      def submit_snapshot
        DependencyGraph::Snapshots.new.create_dependabot_snapshot(
          gh_repo_id: update_job.repo.github_id,
          payload: submission_params
        )
      end

      def log_error(exception)
        Dependabot::Logger.error(
          "code.namespace": "CreateDependencySubmission",
          msg: "Failed to submit dependency snapshot",
          "exception.message": exception.message,
          "exception.type": exception.class.name,
          **update_job.telemetry_attributes,
        )
      end

      def bad_request
        Renderer.render_error(
          status: 400,
          title: "Bad Request",
          detail: "Snapshot payload was invalid, this may be a bug in dependabot-core.",
        )
      end

      def internal_server_error
        Renderer.render_error(
          status: 500,
          title: "Internal Server Error",
          detail: "An unexpected error occurred while submitting the dependency snapshot.",
        )
      end

      def submission_params
        data = request.params[:data]

        # Convert string enum values to symbols in the resolved dependencies
        data[:manifests]&.transform_values! do |manifest|
          manifest.tap do |m|
            m[:resolved]&.transform_values! do |dependency|
              dependency[:relationship] = convert_relationship(dependency[:relationship]) if dependency[:relationship]
              dependency[:scope] = convert_scope(dependency[:scope]) if dependency[:scope]
              dependency
            end
          end
        end

        data.merge("scanned" => Time.now.utc)
      end

      def convert_relationship(value)
        case value
        when "direct" then :RELATIONSHIP_DIRECT
        when "indirect" then :RELATIONSHIP_INDIRECT
        else :RELATIONSHIP_UNKNOWN
        end
      end

      def convert_scope(value)
        case value
        when "runtime" then :SCOPE_RUNTIME
        when "development" then :SCOPE_DEVELOPMENT
        else :SCOPE_UNKNOWN
        end
      end
    end
  end
end
