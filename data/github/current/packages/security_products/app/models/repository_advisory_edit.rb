# typed: true
# frozen_string_literal: true

class RepositoryAdvisoryEdit < ApplicationRecord::Domain::Repositories
  include FilterPipelineHelper
  include Instrumentation::Model
  include UserContentEdit::Core

  belongs_to :repository_advisory

  alias_attribute :user_content_id, :repository_advisory_id

  def user_content
    repository_advisory
  end

  def async_user_content
    async_repository_advisory
  end

  def user_content_type
    "RepositoryAdvisory"
  end

  def global_id
    user_content_edit_id || "RepositoryAdvisoryEdit:#{id}"
  end
end
