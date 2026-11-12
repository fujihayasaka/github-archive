# frozen_string_literal: true

# TODO: This entire endpoint is deprecated in favor of `record_ecosystem_versions`. However, we cannot remove it until:
# 1. `dependabot-core` has been migrated to call the new endpoint.
# 2. all currently supported GHES versions are using this new `dependabot-core` so they no longer rely on this endpoint.

require "renderer"

module Routes
  module UpdateJobs
    class RecordPackageManagerVersion < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.package-managers" => { type: Hash, required: true }

      requires :update_job

      def call
        instrument_package_manager_version
        Renderer.no_content
      end

      private

      def instrument_package_manager_version
        update_job.metrics_metadata ||= {}
        update_job.metrics_metadata["package_managers"] = params.fetch(:data).fetch("package-managers")
        update_job.save
      end
    end
  end
end
