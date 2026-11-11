# typed: strict
# frozen_string_literal: true

module GitHub
  # Identifies the current caller (controller action, background job, or API
  # route) from GitHub.context. Used by configsd read tracking and the
  # CallerContext Faraday middleware.
  module ContextCaller
    # Returns [source_name, source_type] based on the current request context.
    #
    # Examples:
    #   ["repos_controller#show", "controller"]
    #   ["repo_sync_job", "job"]
    #   ["GET /repos/{owner}/{repo}", "api"]
    #   ["unknown", "unknown"]
    sig { returns([String, String]) }
    def self.identify
      tags = GitHub.context[:remote_call_source_datadog_tags]

      if tags&.any? { |t| t.to_s.start_with?("source_type:job") }
        job_tag = tags.find { |t| t.to_s.start_with?("job:") }
        job_name = job_tag&.to_s&.delete_prefix("job:") || "unknown_job"
        [job_name, "job"]
      elsif GitHub.context[:controller].present?
        controller = GitHub.context[:controller].to_s
        action = GitHub.context[:controller_action]
        source = action.present? ? "#{controller}##{action}" : controller
        [source, "controller"]
      elsif GitHub.context[:api_route].present?
        [GitHub.context[:api_route].to_s, "api"]
      else
        %w[unknown unknown]
      end
    end
  end
end
