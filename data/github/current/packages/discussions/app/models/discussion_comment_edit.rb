# typed: true
# frozen_string_literal: true

class DiscussionCommentEdit < ApplicationRecord::Domain::Discussions # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  extend T::Sig

  include UserContentEdit::Core
  include FilterPipelineHelper
  include Instrumentation::Model

  belongs_to :discussion_comment, required: true

  alias_attribute :user_content_id, :discussion_comment_id

  sig { returns(T.untyped) }
  def user_content
    discussion_comment
  end

  sig { params(content: T.untyped).returns(T.untyped) }
  def user_content=(content)
    self.discussion_comment = content
  end

  sig { returns(T.untyped) }
  def async_user_content
    async_discussion_comment
  end

  scope :for_discussion, ->(discussion_id) do
    joins(:discussion_comment).merge(DiscussionComment.for_discussion(discussion_id))
  end

  sig { returns(T.untyped) }
  def user_content_type
    "DiscussionComment"
  end

  sig { returns(T.untyped) }
  def global_id
    "DiscussionCommentEdit:#{id}"
  end
end
