# typed: true
# frozen_string_literal: true

class RepositoryAdvisoryCommentEdit < ApplicationRecord::Domain::Repositories
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :repository_advisory_comment

  alias_attribute :user_content_id, :repository_advisory_comment_id

  def user_content
    repository_advisory_comment
  end

  def async_user_content
    async_repository_advisory_comment
  end

  def user_content_type
    "RepositoryAdvisoryComment"
  end

  def global_id
    user_content_edit_id || "RepositoryAdvisoryCommentEdit:#{id}"
  end
end
