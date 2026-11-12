# frozen_string_literal: true

require "renderer"

module Routes
  module UpdateJobs
    class RecordUpdateJobWarning < Coach::Middleware
      WARNING_TITLE_TRUNC_CHARS = 256
      WARNING_DESCRIPTION_TRUNC_CHARS = 6500

      uses Middlewares::EndpointMetrics, route_class: self
      uses Middlewares::Failbot, route_class: self
      uses Middlewares::CheckUpdateJobToken
      uses Middlewares::CheckUpdateJobProcessing
      uses Middlewares::CheckParams,
           "data.warn-type" => { type: String, required: true },
           "data.warn-title" => { type: String, required: false },
           "data.warn-description" => { type: String, required: false }

      requires :update_job

      def call
        create_update_job_warning unless warning_exists?
        Renderer.no_content
      end

      private

      def create_update_job_warning
        UpdateJobWarning.create!(
          update_job: update_job,
          warn_type: warn_type,
          warn_title: truncated_warning_title,
          warn_description: truncated_warning_desc
        )
      rescue ActiveRecord::RecordInvalid => e
        # Log the validation failure, but do not raise an error
        Rails.logger.warn("Warning creation failed: #{e.message}")
      end

      # Check if a warning with the same type and description already exists.
      def warning_exists?
        update_job.
          update_job_warnings.
          exists?(warn_type: warn_type, warn_title: truncated_warning_title, warn_description: truncated_warning_desc)
      end

      # Truncate title if it exceeds the maximum length.
      def truncated_warning_title
        (warn_title || "").to_s.truncate(WARNING_TITLE_TRUNC_CHARS)
      end

      # Truncate description if it exceeds the maximum length.
      def truncated_warning_desc
        (warn_description || "").to_s.truncate(WARNING_DESCRIPTION_TRUNC_CHARS)
      end

      def warn_type
        mapped_warnings[:warn_type]
      end

      def warn_title
        mapped_warnings[:warn_title]
      end

      def warn_description
        mapped_warnings[:warn_description]
      end

      def mapped_warnings
        @mapped_warnings ||= {
          warn_type: params.dig(:data, :"warn-type"),
          warn_title: params.dig(:data, :"warn-title"),
          warn_description: params.dig(:data, :"warn-description") || "",
        }
      end
    end
  end
end
