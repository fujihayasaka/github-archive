# typed: true
# frozen_string_literal: true

# rubocop:todo GitHub/DatabaseModelsShouldHaveTests
class OrganizationDiscussionPostEdit < ApplicationRecord::Domain::Users
  # rubocop:enable GitHub/DatabaseModelsShouldHaveTests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core
  extend T::Sig

  belongs_to :organization_discussion_post

  alias_attribute :user_content_id, :organization_discussion_post_id

  sig { returns(T.nilable(OrganizationDiscussionPost)) }
  def user_content
    organization_discussion_post
  end

  sig { returns(Promise[T.nilable(OrganizationDiscussionPost)]) }
  def async_user_content
    async_organization_discussion_post
  end

  sig { returns(String) }
  def user_content_type
    "OrganizationDiscussionPost"
  end

  sig { returns(T.any(Integer, String)) }
  def global_id
    user_content_edit_id || "OrganizationDiscussionPostEdit:#{id}"
  end
end
