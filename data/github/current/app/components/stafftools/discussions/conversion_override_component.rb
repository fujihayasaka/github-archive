# typed: true
# frozen_string_literal: true

class Stafftools::Discussions::ConversionOverrideComponent < ApplicationComponent
  attr_reader :discussion, :repository

  SPLUNK_URL = "https://splunk.githubapp.com/en-US/app/gh_reference_app/search"
  SPLUNK_PARAMS = "index=rails discussion_number=%{discussion_number} issue_id=%{issue_id}"

  def initialize(discussion:, repository:)
    @discussion  = discussion
    @repository  = repository
  end

  private

  def render?
    return false unless discussion.present? && repository.present?
    discussion.converting?
  end

  memoize def splunk_url
    begin
      query = {
        q: SPLUNK_PARAMS % {
          discussion_number: discussion.number,
          issue_id: discussion.issue_id,
        }
      }
      "#{SPLUNK_URL}?#{query.to_query}"
    end
  end

  def form_path
    stafftools_repository_discussion_conversion_override_path(
      repository.owner_login,
      repository.name,
      discussion.number
    )
  end
end
