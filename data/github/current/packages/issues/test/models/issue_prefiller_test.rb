# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/query_identifier_helper"
class IssuePrefillerTest < GitHub::TestCase
  include QueryIdentifierHelper

  test "prefilling issues" do
    owner = create :user, plan: "large"
    org = create :organization, admin: owner, plan: "bronze"
    repo = create :repository, owner: org, from_example: :commits_controller_test
    milestone = create :milestone, repository: repo, created_by: owner
    label_bug = create :label, repository: repo, name: "bug"

    create :issue, repository: repo, user: owner
    create :issue, repository: repo, user: owner, assignee: owner
    create :issue, repository: repo, user: owner, milestone: milestone

    pr_issue = create :issue, repository: repo, user: owner
    pr = PullRequest.create_for!(repo, user: owner,
                                         base: "master",
                                         head: "topic",
                                         title: "some other silly changes",
                                         issue: pr_issue)
    pr_issue.pull_request = pr
    pr_issue.labels << label_bug

    repo.issues.each do |issue|
      refute issue.association(:pull_request).loaded?
      refute issue.association(:milestone).loaded?
      if issue.milestone_id
        refute issue.milestone.association(:created_by).loaded?
        refute issue.milestone.association(:repository).loaded?
      end
      refute issue.association(:assignments).loaded?
      refute issue.association(:assignees).loaded?
      refute issue.association(:assignee).loaded?
      refute issue.association(:user).loaded?
      refute issue.association(:assignee).loaded?
      refute issue.association(:labels).loaded?
    end

    IssuePrefiller.prefill(repo.issues, repository: repo)

    repo.issues.each do |issue|
      assert issue.association(:pull_request).loaded?
      assert issue.association(:milestone).loaded?
      if issue.milestone_id
        assert issue.milestone.association(:created_by).loaded?
        assert issue.milestone.association(:repository).loaded?
      end
      assert issue.association(:assignments).loaded?
      assert issue.association(:assignees).loaded?
      assert issue.association(:assignee).loaded?
      assert issue.association(:user).loaded?
      assert issue.association(:labels).loaded?
    end
  end

  test "can prefill closed by" do
    enable_feature_flag(:prefill_issue_closed_by)
    owner = create :user
    repo = create :repository, owner: owner
    issue = create :issue, repository: repo, user: owner
    issue.close(owner)

    assert_nil issue.instance_variable_get(:"@closed_by")

    IssuePrefiller.prefill([issue], current_user: owner)

    assert_equal owner, issue.instance_variable_get(:"@closed_by")
  end

  test "prefill of closed by is batched" do
    enable_feature_flag(:prefill_issue_closed_by)
    owner = create :user
    repo = create :repository, owner: owner
    issues = []
    1..10.times do
      issue = create :issue, repository: repo, user: owner
      issue.close(owner)
      assert_nil issue.instance_variable_get(:"@closed_by")

      issues << issue
    end

    assert_max_query_count(3, ignore_feature_flags: true) do
      assert_query_count_per_table({ profiles: 1, issue_events: 1, users: 1 }) do
        IssuePrefiller.prefill(issues, only_prefill: [:closed_by], current_user: owner)
      end
    end

    issues.each do |issue|
      assert_equal owner, issue.instance_variable_get(:"@closed_by")
    end
  end

  test "can prefill close issue references" do
    ref = create(:close_issue_reference)
    issue = ref.issue

    assert_nil issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([issue], current_user: issue.owner)

    assert_equal 1, issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "can prefill public close issue references without viewer" do
    ref = create(:close_issue_reference)
    issue = ref.issue

    assert_nil issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([issue])

    assert_equal 1, issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "can prefill close issue references count if no ref exists" do
    issue = create(:issue)

    assert_nil issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([issue])

    assert_equal 0, issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "can prefill public close issue references count for pull" do
    ref = create(:close_issue_reference)
    pull_issue = ref.pull_request.issue

    assert_nil pull_issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([pull_issue])

    assert_equal 1, pull_issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "can prefill close issue references count for pull if no ref exists" do
    pr = create(:pull_request, :disable_disk_access)
    issue = pr.issue

    assert_nil issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([issue])

    assert_equal 0, issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "can prefill private xref if viewer has access" do
    user = create(:user)
    repo = create(:private_repository, owner: user)
    issue = create(:issue, repository: repo)
    pr = create(:pull_request, :disable_disk_access, head_ref: "cooler_branch", repository: repo, user: user)
    ref = create(:close_issue_reference, issue: issue, pull_request: pr)

    assert_nil issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([issue], current_user: user)

    assert_equal 1, issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "filters private xref if viewer does not have access" do
    user = create(:user)
    repo = create(:private_repository, owner: user)
    private_pr = create(:pull_request, :disable_disk_access, head_ref: "Blooooop", repository: repo, user: user)
    public_issue = create(:issue)
    ref = create(:close_issue_reference, issue: public_issue, pull_request: private_pr, actor_id: user.id)

    rando_viewer = create(:user)

    assert_nil public_issue.instance_variable_get(:"@close_issue_references_count")

    IssuePrefiller.prefill([public_issue], current_user: rando_viewer)

    assert_equal 0, public_issue.instance_variable_get(:"@close_issue_references_count")
  end

  test "prefilling happens in batches" do
    viewer = create(:user)
    repo = create(:repository, owner: viewer)
    issues = []

    10.times do |i|
      issue = create(:issue, repository: repo)
      issues << issue
      pr = create(:pull_request, :disable_disk_access, head_ref: "cooler_branch #{i}", repository: repo, user: viewer)
      create(:close_issue_reference, issue: issue, pull_request: pr)
    end

    IssuePrefiller.stubs(:batch_size).returns(5)

    _, queries = log_cleaned_queries do
      IssuePrefiller.prefill(repo.issues, current_user: viewer)
    end

    close_issue_references_queries = queries.select do |q|
      q.digested_sql.include?("FROM close_issue_references")
    end
    issue_ids_for_pulls_queries = queries.select do |q|
      q.digested_sql.include?("SELECT issues.id FROM issues WHERE issues.pull_request_id IN ?")
    end

    # 4 batches: 2 for list_xrefs_by_pr_id and 2 for list_xrefs_by_issue_id
    assert_equal 4, close_issue_references_queries.count
    # 2 batches: 2 for fetch_issue_ids_for_pulls_candidate
    assert_equal 2, issue_ids_for_pulls_queries.count
  end

  test "prefills issue type and repo owner if prefill_issue_types is enabled" do
    enable_feature_flag(:issue_types)
    enable_feature_flag(:prefill_issue_types)
    owner = create :user, plan: "large"
    org = create :organization, admin: owner, plan: "bronze"
    issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    issue_ids = []
    repo = create(:private_repository, owner: org)
    1..3.times do
      issue = create :issue, repository: repo, user: owner
      issue.issue_type_id = issue_type.id
      issue.save!
      issue_ids << issue.id
    end

    issues = Issue.where(id: issue_ids)

    assert_max_query_count(5, ignore_feature_flags: true) do
      assert_query_count_per_table({ users: 1, profiles: 1, issue_types: 1, repositories: 1, issues: 1 }) do
        IssuePrefiller.prefill(issues, only_prefill: [:issue_types], current_user: owner)
      end
    end

    assert_max_query_count(0, ignore_feature_flags: true) do
      issue = T.must(issues.first)
      repo = T.must(issue.repository)
      assert T.must(repo.owner).issue_types_enabled?
      assert T.must(issue.issue_type).name
    end
  end

  test "does not prefill issue type and repo owner if prefill_issue_types is disabled" do
    enable_feature_flag(:issue_types)
    disable_feature_flag(:prefill_issue_types)
    owner = create :user, plan: "large"
    org = create :organization, admin: owner, plan: "bronze"
    issue_type = org.issue_types.find_by(name: IssueType::DEFAULTS.first[:name])
    issue_ids = []
    repo = create(:private_repository, owner: org)
    1..3.times do
      issue = create :issue, repository: repo, user: owner
      issue.issue_type_id = issue_type.id
      issue.save!
      issue_ids << issue.id
    end

    issues = Issue.where(id: issue_ids)

    assert_max_query_count(4, ignore_feature_flags: true) do
      assert_query_count_per_table({ users: 1, repositories: 1, issues: 1, profiles: 1 }) do
        IssuePrefiller.prefill(issues, only_prefill: [:issue_types], current_user: owner)
      end
    end

    assert_max_query_count(2, ignore_feature_flags: true) do
      assert_query_count_per_table({ users: 1, issue_types: 1 }) do
        issue = T.must(issues.first)
        repo = T.must(issue.repository)
        assert T.must(repo.owner).issue_types_enabled?
        assert T.must(issue.issue_type).name
      end
    end
  end
end
