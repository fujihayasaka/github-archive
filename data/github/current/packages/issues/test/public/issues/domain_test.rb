# typed: true
# frozen_string_literal: true

require "test_helper"

class Issues::Domain::IssueTest < GitHub::TestCase
  include GitHub::DatabaseQueryWarningsTestHelpers
  include ResiliencyHelpers
  include HydroTestHelpers

  def initialize(*args)
    @domain = T.let(Issues::Domain.new, Issues::Domain)
    super
  end

  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @user = create(:collaborator, repository: @repo, action: :write)
    @other_user = create(:user)
    @issue = create(:issue, repository: @repo)
    @other_issue = create(:issue)
  end

  setup do
    @domain = Issues::Domain.new
  end

  context "#by_number" do
    test "finds issues by their number" do
      assert_no_query_warnings do
        assert_equal @issue, @domain.by_number(@issue.number, repo_id: @repo.id)
      end
    end

    test "returns nil for non-existent issue" do
      assert_nil @domain.by_number(-2, repo_id: @repo.id)
    end
  end

  context "#open_issue_and_pr_counts" do
    test "returns counts of open issues and prs from a list of repository ids" do
      2.times { create(:issue, repository: @repo) }
      create(:issue, repository: @repo, state: :closed)
      create(:pull_request, :disable_disk_access, repository: @repo, user: @user)

      counts = T.must(Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [@repo.id]))

      assert_equal 3, counts[[@repo.id, false]]
      assert_equal 1, counts[[@repo.id, true]]
    end

    if GitHub.spamminess_check_enabled?
      test "returns counts for non spammy open issues and prs from a list of repository ids" do
        repo = create(:repository, name: "simple",  owner: @user)
        spammy_user = create(:user, login: "spammy")
        create(:issue, user: spammy_user, repository: repo)
        2.times { create(:issue, repository: repo) }
        create(:issue, repository: repo, state: :closed)
        create(:pull_request, :disable_disk_access, repository: repo, user: @user)

        perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) do
          spammy_user.mark_as_spammy hard_flag: true
        end

        counts = T.must(Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [repo.id]))

        assert_equal 2, counts[[repo.id, false]]
        assert_equal 1, counts[[repo.id, true]]
      end
    end

    test "returns nil if database fails and return_nil_on_failure is set to true" do
      repo = create :repository, owner: @user, from_example: :pull_request_source

      create :issue, repository: repo
      create :pull_request, :with_mergeable_head, repository: repo

      db_result = prevent_connections_to(ApplicationRecord::IssuesPullRequests) do
        Issues::Domain.new.open_issue_and_pr_counts(repository_ids: [repo.id], return_nil_on_failure: true)
      end

      assert_nil db_result
    end
  end

  context "#create" do
    test "creates a new issue" do
      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
      )

      result = @domain.create(attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal "new issue title", issue.title
      assert_equal "new issue body", issue.body
      assert_equal @repo, issue.repository
      assert_equal @user, issue.user
    end

    test "returns validation error on empty title" do
      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "",
        body: "new issue body",
      )

      result = @domain.create(attributes, @user)
      assert_instance_of GH::Result::Error::Validation, result
    end

    test "creates only one orchestration" do
      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
      )

      result = @domain.create(attributes, @user)

      assert_equal 1, IssueOrchestration.where(issue_id: T.must(result.value).id, type: "CreateIssueOrchestration").count
    end

    test "sets issue type" do
      enable_feature_flag(:issue_types)
      enable_feature_flag(:prefill_issue_types)
      issue_type = @org.issue_types.first

      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        issue_type: issue_type,
      )

      result = @domain.create(attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal issue_type, issue.issue_type
    end

    test "adds labels to the issue" do
      label1 = create(:label, repository: @repo)
      label2 = create(:label, repository: @repo)

      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
        labels: [label1, label2],
      )

      result = @domain.create(attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal [label1, label2].sort, issue.labels.sort
    end

    test "adds milestone to the issue" do
      milestone = create(:milestone, repository: @repo)

      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
        milestone: milestone,
      )

      result = @domain.create(attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal milestone, issue.milestone
    end

    test "handles LockedForRebalance errors" do
      milestone = create(:milestone, repository: @repo)

      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
        milestone: milestone,
      )

      Issue.any_instance.stubs(:save).raises(GitHub::Prioritizable::Context::LockedForRebalance)
      result = @domain.create(attributes, @user)
      assert_instance_of GH::Result::Error::LockedForRebalance, result
    end

    test "adds assignees to the issue" do
      @repo.add_member assignee1 = create(:user)
      @repo.add_member assignee2 = create(:user)

      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
        assignees: [assignee1, assignee2],
      )

      result = @domain.create(attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal [assignee1, assignee2].sort, issue.assignees.sort
    end

    test "sets integration fields" do
      integration = create(:integration, owner: @user)
      attributes = Issues::CreateIssueAttributes.new(
        repository: @repo,
        title: "new issue title",
        body: "new issue body",
      )

      result = @domain.create(attributes, @user, integration: integration)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal integration, issue.performed_via_integration
      assert_equal integration, issue.modifying_integration
    end
  end

  context "#update" do
    test "updates the issue" do
      attributes = Issues::UpdateIssueAttributes.new(
        title: "new title",
        body: "new body",
      )

      result = @domain.update(@issue, attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal "new title", issue.title
      assert_equal "new body", issue.body
    end

    test "updates only the title" do
      old_body = @issue.body
      attributes = Issues::UpdateIssueAttributes.new(
        title: "new title",
      )

      result = @domain.update(@issue, attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_equal "new title", issue.title
      assert_equal old_body, issue.body
    end

    test "deletes the body" do
      old_title = @issue.title
      attributes = Issues::UpdateIssueAttributes.new(
        body: Issues::UpdateOptions::Delete,
      )

      result = @domain.update(@issue, attributes, @user)
      assert_equal true, result.ok?

      issue = T.must(result.value)
      assert_nil issue.body
      assert_equal old_title, issue.title
    end

    test "creates only one orchestration" do
      attributes = Issues::UpdateIssueAttributes.new(
        title: "new title",
        body: "new body",
      )

      result = @domain.update(@issue, attributes, @user)

      assert_equal 1, IssueOrchestration.where(issue_id: @issue.id, type: "UpdateIssueOrchestration").count
    end

    test "publishes hydro message" do
      previous_title = @issue.title
      previous_body = @issue.body

      attributes = Issues::UpdateIssueAttributes.new(
        title: "new title",
        body: "new body",
      )

      result = @domain.update(@issue, attributes, @user)

      message = {
        current_title: "new title",
        current_body: "new body",
        previous_title: previous_title,
        previous_body: previous_body,
      }

      with_hydro_publisher(GitHub.legacy_user_generated_content_publisher) do
        assert_hydro_published(message, schema: "github.v1.IssueUpdate", ignore_extra_keys: true)
      end
    end

    test "returns validation error on empty title" do
      attributes = Issues::UpdateIssueAttributes.new(
        title: "",
      )

      result = @domain.update(@issue, attributes, @user)
      assert_instance_of GH::Result::Error::Validation, result
    end
  end

  context "issue_types" do
    test "returns issue type with case-insensitive search" do
      enable_feature_flag(:issues_types)
      issue_type = create(:issue_type, owner: @org, name: "Super Cool Type")

      found_issue_type = @domain.issue_types.by_organization_and_name(@org, "SupEr COOL tyPE")

      assert_equal issue_type.id, found_issue_type.id
    end

    test "returns nil when issue type cannot be found" do
      enable_feature_flag(:issues_types)
      issue_type = create(:issue_type, owner: @org, name: "Not A Banana")

      found_issue_type = @domain.issue_types.by_organization_and_name(@org, "Banana")

      refute found_issue_type
    end
  end
end
