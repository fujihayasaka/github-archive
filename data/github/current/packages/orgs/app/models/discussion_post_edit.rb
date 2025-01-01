# typed: false
# frozen_string_literal: true

class DiscussionPostEdit < ApplicationRecord::Domain::Users # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :discussion_post

  alias_attribute :user_content_id, :discussion_post_id
  alias_method :user_content, :discussion_post
  alias_method :async_user_content, :async_discussion_post

  def user_content_type
    "DiscussionPost"
  end

  def global_id
    user_content_edit_id || "DiscussionPostEdit:#{id}"
  end
end
