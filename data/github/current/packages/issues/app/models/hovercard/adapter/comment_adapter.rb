# typed: true
# frozen_string_literal: true

class Hovercard::Adapter::CommentAdapter < Issue::Adapter::Base
  TYPES = [
    PlatformTypes::IssueComment,
    PlatformTypes::PullRequestReview
  ]

  attr_reader :author

  def initialize(context, comment:)
    super(context)

    @comment = comment
    @author = comment.user
  end

  def short_body_html(limit: 88)
    @comment.async_truncated_body_html(limit).sync
  end

  sig { override.returns(T.nilable(T::Array[T::Class[T.anything]])) }
  def self.defined_types
    TYPES
  end
end
