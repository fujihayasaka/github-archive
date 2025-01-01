# typed: true
# frozen_string_literal: true

class RepositoryMilestonesSequence < ApplicationRecord::Domain::IssuesPullRequests
  belongs_to :repository
end
