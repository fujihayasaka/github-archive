# typed: true
# frozen_string_literal: true

require "test_helper"

class IssuesLabelsTest < GitHub::TestCase
  fixtures do
    repo = create(:repository)
    @issue = create(:issue, repository: repo)
    @label = create(:label, repository: repo, color: "ff0000", description: "some-description")
  end

  test "copies `repository_id` from the `issue` during create" do
    issues_labels = IssuesLabels.create(issue: @issue, label: @label)

    refute_nil issues_labels.repository_id
    assert_equal issues_labels.repository_id, @issue.repository_id
  end
end
