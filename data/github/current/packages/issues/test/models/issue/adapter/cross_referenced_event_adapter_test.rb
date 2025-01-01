# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class CrossReferencedEventAdapterTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  test "adapting a cross reference does not execute any queries" do
    user = create(:user)
    other_user = create(:user)
    # simulate profile include from issues_controler#current_issue
    build(:profile, user: user)
    repo = create(:repository, owner: user, from_example: :simple)
    repo.add_member(other_user)
    # other issue to issue
    current_issue = create(:issue, repository: repo, user: user)
    other_issue = create(:issue, repository: repo, user: other_user)
    current_issue.record_reference_from(other_issue, user, Time.now)
    # pull to issue
    pull = PullRequest.create_for!(repo,
      user: other_user,
      base: "master",
      head: "cr-line-endings",
      title: "blah",
      body: "blah")
    current_issue.record_reference_from(pull.issue, other_user, Time.now)

    Platform::Security::RepositoryAccess.with_viewer(user) do
      loader = Issue::ShowLoader.new current_issue, repo, user, cap_filter: cap_authorizing_filter
      loader.context.cross_references.each do |cross_reference|
        _adapted, queries = log_cleaned_queries do
          Issue::Adapter::CrossReferencedEventAdapter.new(loader.context, event_id: cross_reference.id)
        end

        assert_equal 0, queries.count
      end
    end
  end

  test "adapting a prs references does not execute any queries" do
    user = create(:user)
    other_user = create(:user)

    # simulate profile include from issues_controler#current_issue
    build(:profile, user: user)
    repo = create(:repository, owner: user, from_example: :simple)

    current_pull = PullRequest.create_for!(repo,
      user: user,
      base: "master",
      head: "cr-line-endings",
      title: "blah 1",
      body: "blah 1")

    # pull to pull reference
    ref = repo.heads.create("topic", repo.heads.find("master").target, user)
    ref.append_commit({ message: "Add file1", committer: user, committed_date: 100.minutes.ago.iso8601 }, user) do |files|
      files.add("file1.txt", "line1\nline2\nline3\n")
    end
    other_pull = PullRequest.create_for!(repo,
      user: user,
      base: "master",
      head: "topic",
      title: "blah 2",
      body: "blah 2")
    current_pull.issue.record_reference_from(other_pull.issue, user, Time.now)

    # issue to pull reference
    other_issue = create(:issue, repository: repo, user: other_user)
    current_pull.issue.record_reference_from(other_issue, other_user, Time.now)

    Platform::Security::RepositoryAccess.with_viewer(user) do
      loader = PullRequest::ShowLoader.new current_pull, repo, user, cap_filter: cap_authorizing_filter
      loader.context.cross_references.each do |cross_reference|
        _adapted, queries = log_cleaned_queries do
          Issue::Adapter::CrossReferencedEventAdapter.new(loader.context, event_id: cross_reference.id)
        end

        assert_equal 0, queries.count
      end
    end
  end

  test "should handle nil target" do
    user = create(:user)
    repo = create(:repository, owner: user)
    current_issue = create(:issue, repository: repo, user: user)
    other_issue = create(:issue, repository: repo, user: user)
    current_issue.record_reference_from(other_issue, user, Time.now)

    loader = Issue::ShowLoader.new current_issue, repo, user, cap_filter: cap_authorizing_filter
    context = loader.context
    cross_reference = context.cross_references.first

    cross_reference.target = nil
    adapter = Issue::Adapter::CrossReferencedEventAdapter.new(context, event_id: cross_reference.id)

    assert_nil adapter.instance_variable_get(:@target)
    assert adapter.instance_variable_get(:@invalid)
  end
end
