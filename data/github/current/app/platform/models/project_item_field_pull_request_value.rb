# typed: true
# frozen_string_literal: true

class Platform::Models::ProjectItemFieldPullRequestValue < Platform::Models::ProjectItemFieldSpecialValue
  attr_reader :pull_requests

  def initialize(pull_requests, item, field)
    super(item, field)
    @pull_requests = pull_requests
    @platform_type_name = "ProjectV2ItemFieldPullRequestValue"
  end
end
