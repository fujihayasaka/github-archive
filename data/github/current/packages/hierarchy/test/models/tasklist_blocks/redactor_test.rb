# typed: false
# frozen_string_literal: true

require "test_helper"

module TasklistBlocks
  class RedactorTest < GitHub::TestCase
    include ConditionalAccess::FilterTestHelper
    include IssuesGraphTestHelpers

    fixtures do
      @admin = create(:verified_user)
      @org = create(:organization, admin: @admin)

      # Spammy member (updated as spammy a few lines down)
      @spammy_user = create(:verified_user)
      @spammy_user.emails.first.verify!
      @org.add_member(@spammy_user)

      # Ordinary member
      @member = create(:verified_user)
      @org.add_member(@member)

      # Site admin viewer
      @site_admin = create(:staff_admin_user)
      @org.add_member(@site_admin)

      @repo = create(:public_repository, from_example: :repository_test_simple)
      @issue = create(:issue, repository: @repo)
      @pull = create(:pull_request, :disable_disk_access, repository: @repo)

      @private_repo_admin = create(:user)
      @private_repo = create(:private_repository, owner: @private_repo_admin)
      @private_issue = create(:issue, repository: @private_repo, user: @private_repo_admin)
      @private_pull = create(:pull_request, :disable_disk_access, repository: @private_repo, user: @private_repo_admin)

      @spammy_issue = create(:issue, repository: @repo, user: @spammy_user)
      @spammy_user.update(spammy: true)
      @spammy_issue.update_column(:user_hidden, true)
    end

    def build_proto_issues(*issues)
      issues.map.with_index do |issue, index|
        position = (index + 1) * 100
        case issue
        when ::Issue
          IssuesGraph::Proto::Issue.new(
            key: IssuesGraph::Proto::Key.new(
              ownerId: issue.repository.owner.id,
              itemId: issue.id,
              primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
                uuid: SecureRandom.uuid,
              )
            ),
            title: issue.title,
            state: issue.open? ? "open" : "closed",
            stateReason: "",
            url: issue.url,
            number: issue.number,
            repoId: issue.repository_id,
            repoName: issue.repository.name,
            userName: issue.user.login,
            labels: [],
            assignees: [],
            position: position
          )
        when TrackingBlocks::DraftIssue
          IssuesGraph::Proto::Issue.new(
            key: IssuesGraph::Proto::Key.new(
              ownerId: 0,
              itemId: 0,
              primaryKey: ::IssuesGraph::Proto::PrimaryKey.new(
                uuid: issue.uuid,
              )
            ),
            title: issue.draft_issue,
            state: "draft",
            stateReason: "",
            url: "",
            number: 0,
            repoId: 0,
            repoName: "",
            userName: "",
            labels: [],
            assignees: [],
            position: position
          )
        else
          issue
        end
      end
    end

    # Translate ::Issue to IssuesGraph::Proto::Issue to TasklistBlocks::Issue to imitate
    # issues with positions generated from Issues Graph
    def get_issues_with_position(*issues)
      build_proto_issues(*issues)
        .map { |proto_issue| TasklistBlocks::Issue.from_proto(issue: proto_issue) }
    end

    context "#issues" do
      test "redacts SSO protected issues that the viewer can see" do
        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: get_issues_with_position(@issue, @private_issue),
          cap_filter: cap_authorizing_filter([@member]),
        )

        assert @issue.readable_by?(@admin)
        assert_kind_of TasklistBlocks::RedactedIssue, redactor.issues.first
        assert_kind_of TasklistBlocks::RedactedIssue, redactor.issues.second
      end

      test "redacts an issue that the viewer is not allowed to see" do
        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: get_issues_with_position(@private_issue),
        )

        refute @private_issue.readable_by?(@admin)
        assert_kind_of TasklistBlocks::RedactedIssue, redactor.issues.first
      end

      test "does not redact an issue that the viewer is allowed see" do
        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: get_issues_with_position(@issue),
        )

        assert_kind_of TasklistBlocks::Issue, redactor.issues.first
      end

      test "does not redact a draft issue" do
        draft_issue = TrackingBlocks::DraftIssue.new(
          draft_issue: "Draft issue",
          owner_id: @admin.id,
          uuid: SecureRandom.uuid,
        )

        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: get_issues_with_position(draft_issue),
        )
        assert_kind_of TasklistBlocks::Issue, redactor.issues.first
      end

      test "shows redacted issues as drafts with original user text as title" do
        tasklist_issues = get_issues_with_position(@private_issue)
        tasklist_issues.first.original_text = "this is what the user typed in"
        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: tasklist_issues,
        )

        refute @private_issue.readable_by?(@admin)
        assert_equal "draft", redactor.issues.first.state
        assert_equal "this is what the user typed in", redactor.issues.first.title
      end

      test "maintains original position for redacted issues" do
        redactor = TasklistBlocks::Redactor.new(
          viewer: @admin,
          issues: get_issues_with_position(@issue, @private_issue),
        )

        assert_equal TasklistBlocks::RedactedIssue, redactor.issues[1].class
        assert_equal 200, redactor.issues[1].position
      end

      if GitHub.spamminess_check_enabled?
        test "redacts an issue created by spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @member,
            issues: get_issues_with_position(@spammy_issue),
          )

          refute_equal @member, @spammy_issue.user
          refute_predicate @member, :site_admin?
          assert_empty redactor.issues
        end

        test "with flag enabled redacts an issue created by spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @member,
            issues: get_issues_with_position(@spammy_issue),
          )

          refute_equal @member, @spammy_issue.user
          refute_predicate @member, :site_admin?
          assert_empty redactor.issues
        end

        test "does not redact an issue created by spammy user when viewing as site admin" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @site_admin,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_predicate @site_admin, :site_admin?
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end

        test "with flag enabled does not redact an issue created by spammy user when viewing as site admin" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @site_admin,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_predicate @site_admin, :site_admin?
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end

        test "does not redact an issue created by spammy user when viewing as spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @spammy_user,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_equal @spammy_user, @spammy_issue.user
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end

        test "with flag on does not redact an issue created by spammy user when viewing as spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @spammy_user,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_equal @spammy_user, @spammy_issue.user
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end
      else
        test "does not redact an issue created by spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @member,
            issues: get_issues_with_position(@spammy_issue),
          )

          refute_equal @member, @spammy_issue.user
          refute_predicate @member, :site_admin?
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end

        test "does not redact an issue created by spammy user when viewing as site admin" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @site_admin,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_predicate @site_admin, :site_admin?
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end

        test "does not redact an issue created by spammy user when viewing as spammy user" do
          redactor = TasklistBlocks::Redactor.new(
            viewer: @spammy_user,
            issues: get_issues_with_position(@spammy_issue),
          )

          assert_equal @spammy_user, @spammy_issue.user
          assert_kind_of TasklistBlocks::Issue, redactor.issues.first
        end
      end
    end
  end
end
