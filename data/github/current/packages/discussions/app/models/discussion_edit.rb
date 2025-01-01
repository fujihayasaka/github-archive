# typed: true
# frozen_string_literal: true

class DiscussionEdit < ApplicationRecord::Domain::Discussions
  extend T::Sig

  include UserContentEdit::Core
  include FilterPipelineHelper
  include Instrumentation::Model

  belongs_to :discussion, required: true

  alias_attribute :user_content_id, :discussion_id

  sig { returns(T.untyped) }
  def user_content
    discussion
  end

  sig { params(content: T.untyped).returns(T.untyped) }
  def user_content=(content)
    self.discussion = content
  end

  sig { returns(T.untyped) }
  def async_user_content
    async_discussion
  end

  sig { returns(T.untyped) }
  def user_content_type
    "Discussion"
  end

  sig { returns(T.untyped) }
  def global_id
    "DiscussionEdit:#{id}"
  end
end
