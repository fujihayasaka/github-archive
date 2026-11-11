# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldReviewerValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :reviewers

  def initialize(reviewers, item, field)
    super(item, field)
    @reviewers = reviewers
    @platform_type_name = "ProjectV2ItemFieldReviewerValue"
  end
end
