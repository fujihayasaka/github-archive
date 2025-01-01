# typed: true
# frozen_string_literal: true

module Dependabot
  module Twirp
    class SuggestedFixesClient < Dependabot::Twirp::BaseClient
      def get_suggested_fix(autofix_job_id:, github_repo_id:, github_pull_request_number:)
        rpc(:GetSuggestedFix, autofix_job_id:, github_repo_id:, github_pull_request_number:)
      end

      def apply_suggested_fix(autofix_job_id:, github_repo_id:, github_pull_request_number:)
        rpc(:ApplySuggestedFix, autofix_job_id:, github_repo_id:, github_pull_request_number:)
      end

      def dismiss_suggested_fix(autofix_job_id:, github_repo_id:, github_pull_request_number:)
        rpc(:DismissSuggestedFix, autofix_job_id:, github_repo_id:, github_pull_request_number:)
      end

      private

      def twirp_class
        DependabotApi::V1::SuggestedFixesClient
      end
    end
  end
end
