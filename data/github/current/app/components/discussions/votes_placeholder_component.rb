# typed: true
# frozen_string_literal: true

module Discussions
  class VotesPlaceholderComponent < ApplicationComponent
    include UsersHelper

    def initialize(target:, discussion: target.discussion, data: {})
      @target = target
      @discussion = discussion
      @data = data
    end

    def sparkle_votes_enabled?
      discussion.repository.sparkle_votes_enabled?
    end

    private

    attr_reader :discussion, :target, :data

    def deferred_content_path
      helpers.cached_path(:discussions_votes_path,
        user_id: discussion.repository_owner_login,
        repository: discussion.repository.name)
    end

    def deferred_content_inputs
      if target.is_a?(Discussion)
        { discussion_id: target.id }
      else
        { comment_id: target.id }
      end
    end
  end
end
