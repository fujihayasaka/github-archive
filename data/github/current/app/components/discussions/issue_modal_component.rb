# typed: strict
# frozen_string_literal: true

module Discussions
  class IssueModalComponent < ApplicationComponent
    extend T::Sig

    # discussion_or_comment - a Discussion or DiscussionComment
    # repository - the Repository the discussion is in
    sig { params(discussion_or_comment: T.any(Discussion, DiscussionComment), repository: Repository).void }
    def initialize(discussion_or_comment:, repository:)
      @discussion_or_comment = discussion_or_comment
      @repository = repository
    end

    private

    sig { returns(T.any(Discussion, DiscussionComment)) }
    attr_reader :discussion_or_comment

    sig { returns(Repository) }
    attr_reader :repository

    delegate :author, to: :discussion_or_comment

    sig { returns(T::Boolean) }
    def render?
      discussion_or_comment.present? && repository.present? && discussion_or_comment.repository_id == repository.id &&
        GitHub.discussions_available_on_platform? && logged_in?
    end

    sig { returns(String) }
    memoize def repo_selector_id
      "discussion-issue-modal-repo-select-#{discussion_or_comment.id}"
    end

    sig { returns(String) }
    def text
      discussion_or_comment.body.presence || discussion_or_comment.try(:title) || ""
    end

    sig { returns(String) }
    def title
      text.split(/\n/, 2).first&.strip || ""
    end

    sig { returns(T.nilable(String)) }
    def reference_text
      if original_reference.present?
        "_Originally posted by @#{author} in #{original_reference}_"
      end
    end

    sig { returns(String) }
    def body
      [text.strip, reference_text].map(&:presence).compact.join("\n\n")
    end

    sig { returns(Integer) }
    def discussion_number
      if discussion_or_comment.is_a?(Discussion)
        discussion_or_comment.number
      else
        discussion_or_comment.try(:discussion_number)
      end
    end

    sig { returns(String) }
    def target_class
      discussion_or_comment.is_a?(Discussion) ? "Discussion" : "Comment"
    end

    sig { returns(String) }
    def original_reference
      anchor = if discussion_or_comment.is_a?(DiscussionComment)
        "##{discussion_or_comment.dom_id}"
      end
      "#{helpers.base_url}#{helpers.discussion_path(discussion_number, repository)}#{anchor}"
    end
  end
end
