# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class IssueAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  test "adapting current issue does not execute any queries" do
    # The repository owner & profile is expected to be preloaded before hitting the ShowLoader.
    repo_owner = create(:user)
    create(:profile, user: repo_owner)

    # loading the profile here actually prevents loading it later in the adapter.
    issue_creator = create(:user)
    create(:profile, user: issue_creator)

    repo = create(:repository, owner: repo_owner)

    issue = create(:issue, repository: repo, user: issue_creator)
    loader = Issue::ShowLoader.new issue, repo, issue_creator, cap_filter: cap_authorizing_filter
    _adapted, queries = log_cleaned_queries do
      issue_adapter = Issue::Adapter::IssueAdapter.new(loader.context,
        timeline_loader: loader.timeline_loader)
    end
    assert_equal 0, queries.count
  end

  test "filtering for tasklist block markdown does not introduce HTML encoding" do
    expected_body = <<~MD.chomp
    <details>
    <summary>This is an issue with non-tasklist content.</summary>
    <p>More details here</p>
    </details>

    ```mermaid
    flowchart TB;
        A[[Hello]]
        B(Bye)
        A --> B;
    ```
    MD

    repo_owner = create(:organization)
    issue_creator = create(:user)
    create(:profile, user: issue_creator)
    repo = create(:repository, owner: repo_owner)
    issue = create(:issue, repository: repo, user: issue_creator, body: expected_body)
    GitHub.flipper[:tasklist_block].enable(repo_owner)

    loader = Issue::ShowLoader.new issue, repo, issue_creator, cap_filter: cap_authorizing_filter
    adapted = Issue::Adapter::IssueAdapter.new(
      loader.context,
      timeline_loader: loader.timeline_loader
    )

    assert_equal expected_body, adapted.body
  end
end
