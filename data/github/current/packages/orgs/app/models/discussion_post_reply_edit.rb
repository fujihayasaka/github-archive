# typed: false
# frozen_string_literal: true

class DiscussionPostReplyEdit < ApplicationRecord::Domain::Users # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :discussion_post_reply

  alias_attribute :user_content_id, :discussion_post_reply_id
  alias_method :user_content, :discussion_post_reply
  alias_method :async_user_content, :async_discussion_post_reply

  def user_content_type
    "DiscussionPostReply"
  end

  def global_id
    user_content_edit_id || "DiscussionPostReplyEdit:#{id}"
  end
end
