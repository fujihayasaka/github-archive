# typed: true
# frozen_string_literal: true

module ComparisonPullRequest
  def build(pull_request_class, comparison, attributes = {})
    attributes = attributes.merge(
      repository: comparison.repo,
      base_user: comparison.base_user,
      base_repository: comparison.base_repo,
      base_ref: comparison.base_revision&.b,
      head_user: comparison.head_user,
      head_repository: comparison.head_repo,
      head_ref: comparison.head_revision&.b,
    )

    pull = pull_request_class.new(attributes)
    pull.record_concrete_commit_points
    pull
  end

  module_function :build
end
