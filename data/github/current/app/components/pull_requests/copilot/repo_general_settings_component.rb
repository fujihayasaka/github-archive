# typed: true
# frozen_string_literal: true

module PullRequests
  module Copilot
    class RepoGeneralSettingsComponent < ApplicationComponent

      attr_accessor :repo

      def initialize(repo:)
        @repo = repo
      end

      def repo_custom_instructions_toggle_form_src
        code_review_repository_settings_path(repo.owner, repo)
      end

      def repo_custom_instructions_toggle_form_csrf_token
        authenticity_token_for(repo_custom_instructions_toggle_form_src)
      end

      private

      memoize def repo_custom_instructions_feature_enabled?
        current_copilot_user_v2&.beta_features_github_chat_enabled? || current_user.feature_flag_enabled?("copilot_code_review_repo_copilot_instructions", default: false)
      end

      # If the repository does not yet have an entry in the
      # copilot_code_review_repository_settings table, set
      # repo_custom_instructions_enabled to true by default.
      memoize def repo_custom_instructions_enabled?
        repo_settings = PullRequests::Copilot::CodeReviewRepositorySettings
          .find_by(repository: repo)

        return true if repo_settings.nil?
        repo_settings.repo_custom_instructions_enabled
      end
    end
  end
end
