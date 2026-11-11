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
        code_review_repository_settings_path(repo.owner, repo, setting: "repo_custom_instructions_enabled")
      end

      def repo_custom_instructions_toggle_form_csrf_token
        authenticity_token_for(repo_custom_instructions_toggle_form_src)
      end

      def repo_auto_approve_toggle_form_src
        code_review_repository_settings_path(repo.owner, repo, setting: "repo_auto_approve_enabled")
      end

      def repo_auto_approve_toggle_form_csrf_token
        authenticity_token_for(repo_auto_approve_toggle_form_src)
      end

      def repo_auto_reject_toggle_form_src
        code_review_repository_settings_path(repo.owner, repo, setting: "repo_auto_reject_enabled")
      end

      def repo_auto_reject_toggle_form_csrf_token
        authenticity_token_for(repo_auto_reject_toggle_form_src)
      end

      def render_general_settings?
        repo_custom_instructions_feature_enabled? ||
          auto_approve_reviews_feature_enabled? ||
          auto_reject_reviews_feature_enabled?
      end

      private

      memoize def repo_custom_instructions_feature_enabled?
        current_copilot_user_v2&.beta_features_github_chat_enabled? || current_user.feature_flag_enabled?("copilot_code_review_repo_copilot_instructions", default: false)
      end

      memoize def merge_readiness_feature_enabled?
        repo.feature_enabled_for_repo_or_owner?(:ccr_show_merge_readiness)
      end

      memoize def auto_approve_reviews_feature_enabled?
        merge_readiness_feature_enabled? && repo.feature_enabled_for_repo_or_owner?(:ccr_auto_approve_reviews)
      end

      memoize def auto_reject_reviews_feature_enabled?
        merge_readiness_feature_enabled? && repo.feature_enabled_for_repo_or_owner?(:ccr_auto_reject_reviews)
      end

      memoize def repo_settings
        PullRequests::Copilot::CodeReviewRepositorySettings.find_by(repository: repo)
      end

      # If the repository does not yet have an entry in the
      # copilot_code_review_repository_settings table, set
      # repo_custom_instructions_enabled to true by default.
      memoize def repo_custom_instructions_enabled?
        return true if repo_settings.nil?
        repo_settings.repo_custom_instructions_enabled
      end

      memoize def repo_auto_approve_enabled?
        return false if repo_settings.nil?
        repo_settings.repo_auto_approve_enabled
      end

      memoize def repo_auto_reject_enabled?
        return false if repo_settings.nil?
        repo_settings.repo_auto_reject_enabled
      end
    end
  end
end
