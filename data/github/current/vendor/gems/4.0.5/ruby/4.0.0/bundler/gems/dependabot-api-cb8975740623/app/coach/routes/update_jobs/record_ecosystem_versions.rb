# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordEcosystemVersions < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           # The recorded versions will vary based on the ecosystem, so we merely ensure it's a hash.
           "data.ecosystem_versions" => { type: Hash, required: true }

      requires :update_job

      def call
        record_ecosystem_versions
        Renderer.no_content
      end

      private

      def record_ecosystem_versions
        update_job.metrics_metadata ||= {}
        update_job.metrics_metadata["ecosystem_versions"] = params.fetch(:data).fetch("ecosystem_versions")
        update_job.save
      end
    end
  end
end
