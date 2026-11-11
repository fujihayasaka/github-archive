# typed: true
# frozen_string_literal: true

class PullRequestSource < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :pull_request

  before_validation :set_repository_id, on: :create
  validates :repository_id, presence: true, on: :create

  enum :source, { codespace: 0 }

  private def set_repository_id
    self.repository_id = pull_request&.repository_id
  end
end
