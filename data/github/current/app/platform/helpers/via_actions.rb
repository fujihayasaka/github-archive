# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    module ViaActions
      extend self

      # Whether or not the request came from GitHub Actions.
      #
      # context: the GraphQL context of the request
      # log_metric: determines if we log a package_file_downloaded metric. Only
      # true when this method is used as a gate for exposing file URL, which
      # we approximate to mean a download has occurred.
      #
      # Returns: Boolean
      def request_via_actions?(context:, log_metric: false, usage_bytes: 0)
        result = if context[:integration].respond_to?(:launch_github_app?)
          tag = "gh.auth.actions_identifier:GITHUB_TOKEN"
          context[:integration].launch_github_app? || context[:integration].launch_lab_github_app?
        elsif context[:forwarded_for]
          tag = "gh.auth.actions_identifier:Actions_IP"
          # Use first segment of X-Forwarded-For value as request origin IP
          GitHub.actions_runner_ips_include?(context[:forwarded_for].split(",")[0])
        else
          false
        end

        if log_metric && result
          GitHub.dogstats.count("package_file_downloaded_size", usage_bytes, tags: [tag]) if usage_bytes > 0
          GitHub.dogstats.increment("package_file_downloaded", tags: [tag])
        end

        result
      end

      def using_internal_schema?(context)
        context[:permission].target == :internal
      end
    end
  end
end
