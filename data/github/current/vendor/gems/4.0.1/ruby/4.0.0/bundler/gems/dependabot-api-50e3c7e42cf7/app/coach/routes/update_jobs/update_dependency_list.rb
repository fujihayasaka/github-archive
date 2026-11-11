# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class UpdateDependencyList < Coach::Middleware
      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing

      requires :update_job

      def call
        Dependabot::Logger.info(
          "code.namespace": "UpdateDependencyList",
          dependency_count: params[:data][:dependencies]&.count || 0,
          file_count: params[:data][:dependency_files]&.count || 0,
          **update_job.telemetry_attributes,
        )

        update_job.update_config.update!(
          monitored_files: sanitized_dependency_files(params[:data][:dependency_files]),
        )

        begin
          record_job_transition
        rescue StandardError => e
          Dependabot::Logger.error("Error recording job processing transition: #{e.message}")
        end

        Renderer.no_content
      # TODO: Remove this rescue once we've cleaned out duplicate update configs
      rescue ActiveRecord::RecordInvalid => e
        raise unless e.message.include?("Directory has already been taken")

        Renderer.no_content
      end

      private

      # Based on mysql text column limit of 65536 with a small safety buffer
      # for headers and unexpected additions
      SERIALIZED_DEPENDENCY_FILES_LENGTH_LIMIT = 65000
      # Serialized as yaml array: - "path"\n
      SERIALIZED_DEPENDENCY_FILE_OVERHEAD = 5

      # Inspect dependency_files and reject any that will cause a failure when persisting to the db
      def sanitized_dependency_files(dependency_files)
        return unless dependency_files

        current_length = 0
        sanitized_files = dependency_files.take_while do |path|
          current_length += path.length + SERIALIZED_DEPENDENCY_FILE_OVERHEAD
          current_length < SERIALIZED_DEPENDENCY_FILES_LENGTH_LIMIT
        end

        if dependency_files.count != sanitized_files.count
          Dependabot::Logger.warn(
            "code.namespace": "UpdateDependencyList",
            skipped_file_count: dependency_files.count - sanitized_files.count,
            msg: "Skipped capturing dependency files that would exceed db limits",
            **update_job.telemetry_attributes,
          )
        end

        sanitized_files
      end

      def record_job_transition
        processing_transition = update_job.history.
                                find { |job_history| job_history.to_state == "processing" }
        return unless processing_transition&.created_at

        duration = Time.current - processing_transition.created_at
        MetricsClient.timing("update_job.update_dependency_list", duration,
                             tags: { package_manager: update_job.update_config.package_manager })
      end
    end
  end
end
