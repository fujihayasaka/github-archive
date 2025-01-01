# typed: true
# frozen_string_literal: true

# This provides a model that we can use to query the `issues_labels` join table directly.
class IssuesLabels < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :issue
  belongs_to :label

  before_create :set_repository_id # rubocop:todo GitHub/AvoidActiveRecordCallbacks

  private

  def set_repository_id
    self.repository_id = self.issue&.repository_id
  end
end
