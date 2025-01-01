# typed: strict
# frozen_string_literal: true

module Discussions
  # Renders the content of a discussion or comment, including the body and a poll, if they exist.
  class BodyAndPollComponent < ApplicationComponent
    extend T::Sig

    renders_one :body_html

    sig do
      params(
        discussion_or_comment: T.any(Discussion, DiscussionComment),
        repository: Repository,
      ).void
    end
    def initialize(discussion_or_comment:, repository:)
      @discussion_or_comment = discussion_or_comment
      @repository = repository
    end

    private

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(Repository) }
    attr_reader :repository

    sig { returns(T::Boolean) }
    memoize def has_displayable_poll?
      discussion = discussion_or_comment
      return false unless discussion.is_a?(Discussion)
      discussion.poll.present?
    end

    sig { returns(T::Boolean) }
    memoize def display_body_section?
      body_html? || !has_displayable_poll?
    end

    sig { returns(String) }
    memoize def empty_body_text
      discussion_or_comment.is_a?(Discussion) ? "No description provided." : "This comment was deleted."
    end
  end
end
