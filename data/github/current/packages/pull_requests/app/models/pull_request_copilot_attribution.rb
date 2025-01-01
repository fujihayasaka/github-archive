# typed: true
# frozen_string_literal: true

class PullRequestCopilotAttribution < ApplicationRecord::Domain::IssuesPullRequests
  validates_presence_of :pull_request, :user

  belongs_to :pull_request
  belongs_to :user

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  private def set_repository_id
    self.repository_id = pull_request&.repository_id
  end
end
