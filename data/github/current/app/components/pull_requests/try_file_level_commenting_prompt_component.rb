# typed: true
# frozen_string_literal: true

module PullRequests
  class TryFileLevelCommentingPromptComponent < ApplicationComponent
    FIRST_DIFF_ENTRY_INDEX = 0

    def initialize(pull_request:, repository:, commentable:, diff_entry_index:)
      @pull_request     = pull_request
      @repository       = repository
      @commentable      = commentable
      @diff_entry_index = diff_entry_index
    end

    private

    attr_reader :pull_request, :repository, :commentable, :diff_entry_index

    def render?
      return false if repository&.feature_flag_enabled?(:hide_file_level_commenting_popover, default: false)
      return false unless logged_in?
      return false unless repository&.feature_flag_enabled?(:file_level_commenting, default: false)
      return false unless commentable
      return false unless pull_request
      return false if pull_request.merged?
      return false if pull_request.closed?
      return false if current_user.dismissed_notice?("try_file_level_commenting")
      return false if diff_entry_index != FIRST_DIFF_ENTRY_INDEX
      true
    end
  end
end
