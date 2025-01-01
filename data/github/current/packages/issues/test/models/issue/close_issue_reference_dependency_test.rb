# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/platform/pull_request_resolver_helpers"
require "test_helpers/query_identifier_helper"

class TestFilter < ::ConditionalAccess::Filter
  include ConditionalAccess::Policy::TwoFactorAuthn
  include ConditionalAccess::Policy::SAML
  include ConditionalAccess::Policy::IpAllowlist
  include QueryIdentifierHelper

  attr_reader :user

  def initialize(callback, user)
    @user = user
    super(callback)
  end

  def conditional_access_policies
    [:ip_allowlist, :saml, :two_factor]
  end

  def location
    :test
  end

  def anonymous?
    @user.nil?
  end

  def actor
    @user
  end

  def actor_ip
    "127.0.0.1"
  end
end

class IssueCloseIssueReferenceDependencyTest < GitHub::TestCase
  include PlatformTestHelpers::PullRequestResolverHelpers
  include HydroTestHelpers

  fixtures do
    # creates a repo and returns [@merged_pr, @open_pr, and @closed_pr]
    build_pulls
    @repo = @open_pr.repository

    # open pr and merged pr share the same repo
    @harry = create :user, plan: "pro"
    @hermione = create :user
    @draco = create :user

    @staffer = create :staff_admin_user
    @anonymous = nil

    @private_repo = create :private_repository, owner: @harry
    @private_repo.add_member @draco

    base_ref = @private_repo.heads.find_or_build("master")
    append_dummy_commit(base_ref)

    open_ref = @private_repo.heads.create("leave-me-open", base_ref.target, @harry)
    open_ref2 = @private_repo.heads.create("leave-me-open2", base_ref.target, @draco)
    closed_ref = @private_repo.heads.create("close-me", base_ref.target, @harry)
    merged_ref = @private_repo.heads.create("merge-me", base_ref.target, @harry)

    append_dummy_commit(open_ref)
    append_dummy_commit(open_ref2)
    append_dummy_commit(closed_ref)
    append_dummy_commit(merged_ref)

    @private_open_pr = create(:pull_request, build_pull_attrs(repo: @private_repo, user: @harry).merge(head_ref: "leave-me-open"))
    @private_open_pr2 = create(:pull_request, build_pull_attrs(repo: @private_repo, user: @draco).merge(head_ref: "leave-me-open2"))

    Timecop.freeze(3.seconds.from_now) do
      @private_closed_pr = create(:pull_request, build_pull_attrs(repo: @private_repo, user: @harry).merge(head_ref: "close-me"))
    end
    @private_closed_pr.close(closer = @private_repo.owner)

    Timecop.freeze(9.seconds.from_now) do
      @private_merged_pr = create(:pull_request, build_pull_attrs(repo: @private_repo, user: @harry).merge(head_ref: "merge-me"))
    end
    @private_merged_pr.merge
    build_private_org_pull_requests

    # active issue with inactive repo reference
    @active_repo = create :repository
    @active_issue = create :issue, repository: @active_repo
    @inactive_user = create :user, login: "delete-me"
    @inactive_repo = create :repository, owner: @inactive_user, name: "delete-me-repo"
  end

  def build_private_org_pull_requests
    @org = create :organization, admin: @harry
    @private_org_repo = create :private_repository, owner: @org

    @two_factor_org = create :business_plus_org, admin: @harry
    @two_factor_org_repo = create :private_repository, owner: @two_factor_org

    base_ref = @private_org_repo.heads.find_or_build("master")
    two_factor_base_ref = @two_factor_org_repo.heads.find_or_build("master")
    append_dummy_commit(base_ref)
    append_dummy_commit(two_factor_base_ref)

    open_ref = @private_org_repo.heads.create("leave-me-open", base_ref.target, @harry)
    open_ref2 = @two_factor_org_repo.heads.create("leave-me-open2", two_factor_base_ref.target, @harry)
    closed_ref = @private_org_repo.heads.create("close-me", base_ref.target, @harry)
    merged_ref = @private_org_repo.heads.create("merge-me", base_ref.target, @harry)

    append_dummy_commit(open_ref)
    append_dummy_commit(open_ref2)
    append_dummy_commit(closed_ref)
    append_dummy_commit(merged_ref)

    @private_org_open_pr = create(:pull_request, build_pull_attrs(repo: @private_org_repo, user: @harry).merge(head_ref: "leave-me-open"))
    @private_org_open_pr2 = create(:pull_request, build_pull_attrs(repo: @two_factor_org_repo, user: @harry).merge(head_ref: "leave-me-open2"))

    Timecop.freeze(3.seconds.from_now) do
      @private_org_closed_pr = create(:pull_request, build_pull_attrs(repo: @private_org_repo, user: @harry).merge(head_ref: "close-me"))
    end
    @private_org_closed_pr.close(closer = @private_org_repo.owner.admin)

    Timecop.freeze(9.seconds.from_now) do
      @private_org_merged_pr = create(:pull_request, build_pull_attrs(repo: @private_org_repo, user: @harry).merge(head_ref: "merge-me"))
    end
    @private_org_merged_pr.merge
  end

  def build_draft_pr
    draft_ref = @repo.heads.create("bloop", @repo.heads.find_or_build("master").target, @owner)
    draft_ref.append_commit({ message:  "a change", committer: @owner }, @owner) do |files|
      files.add("file002", "foo")
    end

    draft_pr = create(:pull_request, repository: @repo, base_ref: "master", head_ref: "bloop")
    draft_pr.update(draft: true)
    draft_pr
  end

  test "enqueues an update job on PR create" do
    issue = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue.number}.", repository: @repo)

    assert_enqueued_with(job: UpdateCloseIssueReferencesJob, args: [pull_issue.id]) do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)
      end
    end
  end

  test "enqueues an update job on PR issue update" do
    issue1 = create(:issue, repository: @repo)
    issue2 = create(:issue, repository: @repo)
    pull_issue = create(:issue, body: "This fixes ##{issue1.number}.", repository: @repo)
    create(:pull_request, :disable_disk_access, issue: pull_issue, repository: @repo)

    pull_issue.body += " And also closes ##{issue2.number}!"
    assert_enqueued_with(job: UpdateCloseIssueReferencesJob, args: [pull_issue.id]) do
      perform_enqueued_jobs only: [IssueOrchestration.job_class] do
        pull_issue.save!
      end
    end
  end

  test "deletes CloseIssueReference when destroyed" do
    ref = create(:close_issue_reference)

    assert_difference("CloseIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { ref.issue.destroy }
    end

    refute CloseIssueReference.exists?(ref.id)
  end

  test "deletes CloseIssueReference for pull request when destroyed" do
    ref = create(:close_issue_reference)

    assert_difference("CloseIssueReference.count", -1) do
      perform_enqueued_jobs(only: [DestroyDependentRecordsJob]) { ref.pull_request.issue.destroy }
    end

    refute CloseIssueReference.exists?(ref.id)
  end

  context "#may_be_closed_by?" do
    test "true if close_issue_reference exists" do
      ref = create(:close_issue_reference)
      assert ref.issue.may_be_closed_by?(ref.pull_request.id)
    end

    test "false if no close_issue_reference exists" do
      ref = create(:close_issue_reference)
      rando_pull = create(:pull_request, :disable_disk_access, repository: @repo)
      refute ref.issue.may_be_closed_by?(rando_pull.id)
    end

    test "false if issue is already closed" do
      ref = create(:close_issue_reference)
      issue = ref.issue
      issue.close!
      refute ref.issue.may_be_closed_by?(ref.pull_request.id)
    end
  end

  context "#closed_by_pull_requests_references_for" do
    context "prs referencing an issue in the same repo" do
      test "returns open PRs referencing the issue" do
        issue = create :issue, repository: @repo, user: @harry
        create :close_issue_reference, issue: issue, pull_request: @open_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @open_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @open_pr, closed_by_prs[0]
      end

      test "returns merged PRs referencing the issue" do
        issue = create :issue, repository: @repo, user: @harry
        create :close_issue_reference, issue: issue, pull_request: @merged_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]
      end

      test "does not return closed PRs referencing the issue when excluded" do
        issue = create :issue, repository: @repo, user: @harry
        create :close_issue_reference, issue: issue, pull_request: @closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [], include_closed_prs: false)

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, include_closed_prs: false)

        assert_empty closed_by_prs
      end

      test "returns empty if referenced pull was deleted" do
        issue = create :issue, repository: @repo, user: @harry
        create :close_issue_reference, issue: issue, pull_request: @open_pr
        @open_pr.delete
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_empty closed_by_prs
      end
    end

    context "public repo prs referencing an issue from a public repo" do
      test "returns open PRs referencing the issue" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @open_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @open_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @open_pr, closed_by_prs[0]
      end

      test "returns merged PRs referencing the issue" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @merged_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]
      end

      test "returns closed PRs referencing the issue by default" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @closed_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @closed_pr, closed_by_prs[0]
      end

      test "returns closed PRs when explicitly requested" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [], include_closed_prs: true)

        assert_equal 1, closed_by_prs.length
        assert_equal @closed_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @closed_pr, closed_by_prs[0]
      end

      test "does not return closed PRs referencing the issue when excluding them" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [], include_closed_prs: false)

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, include_closed_prs: false)

        assert_empty closed_by_prs
      end

      test "returns PRs ordered by state when requested" do
        draft_pr = build_draft_pr

        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @open_pr
        create :close_issue_reference, issue: issue, pull_request: draft_pr
        create :close_issue_reference, issue: issue, pull_request: @merged_pr
        create :close_issue_reference, issue: issue, pull_request: @closed_pr

        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 4, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]
        assert_equal @open_pr, closed_by_prs[1]
        assert_equal draft_pr, closed_by_prs[2]
        assert_equal @closed_pr, closed_by_prs[3]

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 4, closed_by_prs.length
        assert_equal @merged_pr, closed_by_prs[0]
        assert_equal @open_pr, closed_by_prs[1]
        assert_equal draft_pr, closed_by_prs[2]
        assert_equal @closed_pr, closed_by_prs[3]
      end

      context "cap_filtered_closed_by_pull_requests_references_for" do
        test "does not execute unexpected queries when requested (no n+1s)" do
          issue = create :issue

          private_repo = create(:private_repository, name: "Harry's private repo", owner: @harry, description: "Harry's private repo")
          private_repo.add_member(@hermione)
          base_ref = private_repo.heads.find_or_build("master")
          append_dummy_commit(base_ref)
          pull_attrs = build_pull_attrs(repo: private_repo, user: @harry)

          5.times do |index|
            ref = private_repo.heads.create("#{index}-ref", base_ref.target, @harry)
            append_dummy_commit(ref)
            pr = create :pull_request, pull_attrs.merge(head_ref: "#{index}-ref")
            create :close_issue_reference, issue: issue, pull_request: pr
          end

          filter = TestFilter.new(self, @hermione)

          _result, queries = log_cleaned_queries do
            closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)
            assert_equal 5, closed_by_prs.length
          end

          assert_operator 10, :<=, queries.length
        end

        test "does not execute unexpected queries when requested (no n+1s) with limit" do
          issue = create :issue

          private_repo = create(:private_repository, name: "Harry's private repo", owner: @harry, description: "Harry's private repo")
          private_repo.add_member(@hermione)
          base_ref = private_repo.heads.find_or_build("master")
          append_dummy_commit(base_ref)
          pull_attrs = build_pull_attrs(repo: private_repo, user: @harry)

          5.times do |index|
            ref = private_repo.heads.create("#{index}-ref", base_ref.target, @harry)
            append_dummy_commit(ref)
            pr = create :pull_request, pull_attrs.merge(head_ref: "#{index}-ref")
            create :close_issue_reference, issue: issue, pull_request: pr
          end

          filter = TestFilter.new(self, @hermione)

          _result, queries = log_cleaned_queries do
            closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, limit: 100)
            assert_equal 5, closed_by_prs.length
          end
          expected_queries = TestEnv.test_all_features? ? 11 : 51 # one more for the `batch` ar method
          assert_operator queries.length, :<=, expected_queries

          issue.reload

          _result, queries = log_cleaned_queries do
            closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, limit: 100, batch_size: 10)
            assert_equal 5, closed_by_prs.length
          end
          expected_queries = TestEnv.test_all_features? ? 17 : 57 # one more for the `batch` ar method, 9 more for 2nd round of fetches
          assert_operator queries.length, :<=, expected_queries

          issue.reload

          _result, queries = log_cleaned_queries do
            closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, limit: 3, batch_size: 1000)
            assert_equal 3, closed_by_prs.length
          end

          assert_operator 8, :<=, queries.length
        end

        test "return only manually linked issues" do
          issue = create :issue

          private_repo = create(:private_repository, name: "Harry's private repo", owner: @harry, description: "Harry's private repo")
          private_repo.add_member(@hermione)
          base_ref = private_repo.heads.find_or_build("master")
          append_dummy_commit(base_ref)
          pull_attrs = build_pull_attrs(repo: private_repo, user: @harry)

          5.times do |index|
            ref = private_repo.heads.create("#{index}-ref", base_ref.target, @harry)
            append_dummy_commit(ref)
            pr = create :pull_request, pull_attrs.merge(head_ref: "#{index}-ref")
            create :close_issue_reference, issue: issue, pull_request: pr
          end

          filter = TestFilter.new(self, @hermione)

          _result, queries = log_cleaned_queries do
            closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, user_linked_only: true, cap_filter: filter)
            assert_equal 0, closed_by_prs.length
          end
        end

        test "does not return a PR reference from a deleted user's account" do
          example_repo :pull_request_source, @inactive_repo
          pull_request = create :pull_request, :with_mergeable_head, repository: @inactive_repo
          # reference between an existing issue and pull request from a repository that will be inactive
          create :close_issue_reference, issue: @active_issue, pull_request: pull_request

          # Active repo with pull request reference
          filter = TestFilter.new(self, @active_issue.owner)
          pull_request_references = @active_issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @active_issue.owner, cap_filter: filter)
          assert @inactive_repo.reload.active?
          assert pull_request.reload
          assert pull_request_references

          # user deletes account
          @inactive_user.destroy

          # Inactive repo with pull request reference
          pull_request_references = @active_issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @active_issue.owner, cap_filter: filter)
          refute @inactive_repo.reload.active?
          assert pull_request.reload
          assert_empty pull_request_references
        end
      end
    end

    context "public repo prs referencing an issue from a private repo" do
      test "does not return issue for staff user staff if not accessible" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_merged_pr

        staff_user = create(:user, :staff)
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_equal 0, closed_by_prs.length

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_equal 0, closed_by_prs.length
      end
    end

    context "private repo prs referencing an issue from a public repo" do
      test "returns merged PRs the viewer can access" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_merged_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @harry, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @private_merged_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @harry)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @harry, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @private_merged_pr, closed_by_prs[0]
      end

      test "returns open PRs the viewer can access" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_open_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @harry, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @private_open_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @harry)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @harry, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @private_open_pr, closed_by_prs[0]
      end

      test "returns closed PRs by default" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @harry, unauthorized_organization_ids: [])

        assert_equal 1, closed_by_prs.length
        assert_equal @private_closed_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @harry)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @harry, cap_filter: filter)

        assert_equal 1, closed_by_prs.length
        assert_equal @private_closed_pr, closed_by_prs[0]
      end

      test "does not return closed PRs referencing the issue when explicitly excluding them" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @harry, unauthorized_organization_ids: [], include_closed_prs: false)

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @harry)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @harry, cap_filter: filter, include_closed_prs: false)

        assert_empty closed_by_prs
      end

      test "returns closed PRs when requested" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_closed_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @harry, unauthorized_organization_ids: [], include_closed_prs: true)

        assert_equal 1, closed_by_prs.length
        assert_equal @private_closed_pr, closed_by_prs[0]

        filter = TestFilter.new(self, @harry)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @harry, cap_filter: filter, include_closed_prs: true)

        assert_equal 1, closed_by_prs.length
        assert_equal @private_closed_pr, closed_by_prs[0]
      end

      test "does not return any PRs the viewer cannot access" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_open_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

        assert_empty closed_by_prs
      end

      test "gracefully handles order_by_state when user cannot access PRs" do
        issue = create :issue
        create :close_issue_reference, issue: issue, pull_request: @private_open_pr
        closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [], order_by_state: true)

        assert_empty closed_by_prs

        filter = TestFilter.new(self, @hermione)
        closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter, order_by_state: true)

        assert_empty closed_by_prs
      end
    end

    context "private org repo prs referencing an issue from a public repo" do
      context "member with read access" do
        test "returns merged PRs" do
          @org.add_member(@hermione, action: :read)

          issue = create :issue
          create :close_issue_reference, issue: issue, pull_request: @private_org_merged_pr
          closed_by_prs = issue.reload.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_merged_pr, closed_by_prs[0]

          filter = TestFilter.new(self, @hermione)
          closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_merged_pr, closed_by_prs[0]
        end

        test "returns open PRs" do
          @org.add_member(@hermione, action: :read)

          issue = create :issue
          create :close_issue_reference, issue: issue, pull_request: @private_org_open_pr
          closed_by_prs = issue.reload.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_open_pr, closed_by_prs[0]

          filter = TestFilter.new(self, @hermione)
          closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_open_pr, closed_by_prs[0]
        end
      end

      context "member with write access" do
        test "returns merged PRs" do
          @org.add_member(@hermione, action: :write)

          issue = create :issue
          create :close_issue_reference, issue: issue, pull_request: @private_org_merged_pr
          closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_merged_pr, closed_by_prs[0]

          filter = TestFilter.new(self, @hermione)
          closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_merged_pr, closed_by_prs[0]
        end

        test "returns open PRs" do
          @org.add_member(@hermione, action: :write)

          issue = create :issue
          create :close_issue_reference, issue: issue, pull_request: @private_org_open_pr
          closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_open_pr, closed_by_prs[0]

          filter = TestFilter.new(self, @hermione)
          closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

          assert_equal 1, closed_by_prs.length
          assert_equal @private_org_open_pr, closed_by_prs[0]
        end
      end

      context "not a member" do
        test "does not return closed PRs" do
          issue = create :issue
          create :close_issue_reference, issue: issue, pull_request: @private_org_closed_pr
          closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

          assert_empty closed_by_prs

          filter = TestFilter.new(self, @hermione)
          closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

          assert_empty closed_by_prs
        end
      end
    end

    test "does not skip pr xref if viewer is blocked by pr owner" do
      repo = create :repository
      issue = create :issue, repository: repo, user: @hermione
      create :close_issue_reference, issue: issue, pull_request: @open_pr

      GitHub.context.push(actor_id: @hermione.id)
      @open_pr.user.block @hermione
      assert @hermione.blocked_by? @open_pr.user

      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

      assert_equal 1, closed_by_prs.length
      assert_equal @open_pr, closed_by_prs[0]

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_equal 1, closed_by_prs.length
      assert_equal @open_pr, closed_by_prs[0]
    end

    test "does not skip pr xref if viewer blocked the pr owner" do
      repo = create :repository
      issue = create :issue, repository: repo, user: @hermione
      create :close_issue_reference, issue: issue, pull_request: @open_pr

      GitHub.context.push(actor_id: @hermione.id)
      @hermione.block @open_pr.user
      assert @open_pr.user.blocked_by? @hermione

      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

      assert_equal 1, closed_by_prs.length
      assert_equal @open_pr, closed_by_prs[0]

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_equal 1, closed_by_prs.length
      assert_equal @open_pr, closed_by_prs[0]
    end

    test "skips referencing spammy prs" do
      # make PR authored by a spammy user
      @open_pr.update_column(:user_hidden, true)
      issue = create :issue, repository: @repo, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr
      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

      assert_empty closed_by_prs

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_empty closed_by_prs
    end

    test "skips referencing spammy prs for anonymous user" do
      # make PR authored by a spammy user
      @open_pr.update_column(:user_hidden, true)
      issue = create :issue, repository: @repo, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr
      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @anonymous, unauthorized_organization_ids: [])

      assert_empty closed_by_prs

      filter = TestFilter.new(self, @anonymous)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @anonymous, cap_filter: filter)

      assert_empty closed_by_prs
    end

    test "does not skip referencing spammy prs for staff" do
      # make PR authored by a spammy user
      @open_pr.update_column(:user_hidden, true)
      issue = create :issue, repository: @repo, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr
      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @staffer, unauthorized_organization_ids: [])

      refute_empty closed_by_prs

      filter = TestFilter.new(self, @staffer)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @staffer, cap_filter: filter)

      refute_empty closed_by_prs
    end

    test "skips referencing spammy repo" do
      # make repo authored by a spammy user
      @repo.update_column(:user_hidden, true)
      # create an issue from different repo
      issue = create :issue, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr

      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

      assert_empty closed_by_prs

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_empty closed_by_prs
    end

    test "skips referencing spammy repo for anonymous user" do
      # make repo authored by a spammy user
      @repo.update_column(:user_hidden, true)
      # create an issue from different repo
      issue = create :issue, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr

      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @anonymous, unauthorized_organization_ids: [])

      assert_empty closed_by_prs

      filter = TestFilter.new(self, @anonymous)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @anonymous, cap_filter: filter)

      assert_empty closed_by_prs
    end

    test "does not skip referencing spammy repo for staff" do
      # make repo authored by a spammy user
      @repo.update_column(:user_hidden, true)
      # create an issue from different repo
      issue = create :issue, user: @harry
      create :close_issue_reference, issue: issue, pull_request: @open_pr

      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @staffer, unauthorized_organization_ids: [])

      refute_empty closed_by_prs

      filter = TestFilter.new(self, @staffer)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @staffer, cap_filter: filter)

      refute_empty closed_by_prs
    end

    test "returns prs even if the author is nil" do
      @private_repo.add_member @hermione
      @private_open_pr2.user.delete

      issue = create :issue, repository: @private_repo, user: @hermione
      create :close_issue_reference, issue: issue, pull_request: @private_open_pr2, actor_id: @hermione.id
      closed_by_prs = issue.closed_by_pull_requests_references_for(viewer: @hermione, unauthorized_organization_ids: [])

      assert_equal 1, closed_by_prs.length
      assert_equal @private_open_pr2, closed_by_prs[0]

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_equal 1, closed_by_prs.length
      assert_equal @private_open_pr2, closed_by_prs[0]
    end

    test "skips referencing prs from unauthorized org" do
      @two_factor_org.add_member(@hermione, action: :write)
      @two_factor_org_repo.add_member(@hermione)
      issue = create :issue, repository: @two_factor_org_repo, user: @hermione
      create :close_issue_reference, issue: issue, pull_request: @private_org_open_pr2, actor_id: @hermione.id

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_equal 1, closed_by_prs.length
      assert_equal @private_org_open_pr2, closed_by_prs[0]

      GitHub.flipper[:cap_2fa_policy_enabled].enable
      GitHub.flipper[:two_factor_cap_enforcement].enable(@two_factor_org)
      @two_factor_org.enable_two_factor_required(actor: @harry)

      filter = TestFilter.new(self, @hermione)
      closed_by_prs = issue.cap_filtered_closed_by_pull_requests_references_for(viewer: @hermione, cap_filter: filter)

      assert_empty closed_by_prs
    end

  end

  context "#close_issue_references_count" do
    test "returns close issue reference count that the viewer can see" do
      GitHub.context.push(actor_id: @harry.id)
      ref = create(:close_issue_reference, actor_id: @harry)
      issue = ref.issue

      assert_equal 1, issue.close_issue_references_count
    end

    test "returns close issue reference count if viewer is nil" do
      ref = create(:close_issue_reference)
      issue = ref.issue

      assert_equal 1, issue.close_issue_references_count
    end
  end

  unless GitHub.enterprise?
    context "Hydro instrumentation" do
      test "pr references an issue publishes a hydro event" do
        issue = create :issue, repository: @repo, user: @harry
        create :close_issue_reference, issue: issue, pull_request: @open_pr, actor_id: @hermione.id

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@hermione),
            issue_repository: Hydro::EntitySerializer.repository(issue.repository),
            issue: Hydro::EntitySerializer.issue(issue),
            pull_request: Hydro::EntitySerializer.pull_request(@open_pr),
            pull_request_author: Hydro::EntitySerializer.user(@owner),
            source: "XREF",
          }, schema: "github.v1.CloseIssueReferenceConnected")
        end
      end

      test "deleting a close issue reference publishes a hydro event" do
        issue = create :issue, repository: @repo, user: @harry
        issue_reference = create :close_issue_reference, issue: issue, pull_request: @open_pr, actor_id: @hermione.id

        issue_reference.destroy

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do

          assert_hydro_published({
            actor: Hydro::EntitySerializer.user(@hermione),
            issue_repository: Hydro::EntitySerializer.repository(issue.repository),
            issue: Hydro::EntitySerializer.issue(issue),
            pull_request: Hydro::EntitySerializer.pull_request(@open_pr),
            pull_request_author: Hydro::EntitySerializer.user(@owner),
            source: "XREF",
          }, schema: "github.v1.CloseIssueReferenceDisconnected")
        end
      end

      test "destroying a close issue reference does not publish a hydro event when repository has already been deleted" do
        issue = create :issue, repository: @repo, user: @harry
        issue_reference = create :close_issue_reference, issue: issue, pull_request: @open_pr, actor_id: @hermione.id

        @repo.delete
        issue_reference.reload.destroy

        with_hydro_publisher(GitHub.low_latency_hydro_publisher) do
          refute_hydro_messages(schema: "github.v1.CloseIssueReferenceDisconnected")
        end
      end
    end
  end
end
