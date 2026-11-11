# typed: true
# frozen_string_literal: true

class Platform::Models::CandidateReviewer
  # A candidate reviewer returned from searching for reviewers

  def initialize(reviewer:)
    @reviewer = reviewer
  end

  attr_reader :reviewer
end
