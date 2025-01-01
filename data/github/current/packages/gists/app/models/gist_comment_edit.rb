# typed: false
# frozen_string_literal: true

class GistCommentEdit < ApplicationRecord::Domain::Gists # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :gist_comment

  alias_attribute :user_content_id, :gist_comment_id
  alias_method :user_content, :gist_comment
  alias_method :async_user_content, :async_gist_comment

  def user_content_type
    "GistComment"
  end

  def global_id
    user_content_edit_id || "GistCommentEdit:#{id}"
  end
end
