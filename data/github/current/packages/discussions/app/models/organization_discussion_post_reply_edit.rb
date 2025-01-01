# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class OrganizationDiscussionPostReplyEdit < ApplicationRecord::Domain::Users
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core
  extend T::Sig

  belongs_to :organization_discussion_post_reply

  alias_attribute :user_content_id, :organization_discussion_post_reply_id

  sig { returns(T.nilable(OrganizationDiscussionPostReply)) }
  def user_content
    organization_discussion_post_reply
  end

  sig { returns(T.nilable(Promise[OrganizationDiscussionPostReply])) }
  def async_user_content
    async_organization_discussion_post_reply
  end

  sig { returns(String) }
  def user_content_type
    "OrganizationDiscussionPostReply"
  end

  sig { returns(T.any(Integer, String)) }
  def global_id
    user_content_edit_id || "OrganizationDiscussionPostReplyEdit:#{id}"
  end
end
