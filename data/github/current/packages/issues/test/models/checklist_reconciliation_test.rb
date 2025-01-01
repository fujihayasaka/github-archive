# typed: true
# frozen_string_literal: true

require "test_helper"

class ChecklistReconciliationTest < GitHub::TestCase
  fixtures do
    @user = create(:paid_user, login: "repo-owner")
    @other = create(:user, login: "other-user")
    @deleted_user = create(:user, login: "deleted-user")
    @repo = create(:private_repository, owner: @user, name: "test_repo")
    @repo.add_member(@deleted_user, action: :write)
    @issue1 = create(:issue, number: 1, repository: @repo, user: @user)
    @issue2 = create(:issue, number: 2, repository: @repo, user: @user)
    @issue3 = create(:issue, number: 3, repository: @repo, user: @user)
    @issue4 = create(:issue, number: 4, repository: @repo, user: @user)
    @issue5 = create(:issue, number: 5, repository: @repo, user: @user)
    @issue6 = create(:issue, number: 6, repository: @repo, user: @user)

    @pr = create(:pull_request, :disable_disk_access, repository: @repo, user: @user)
  end

  setup do
    GitHub.flipper[:extract_checklists].enable(@repo)
  end

  context "extraction logic" do
    test "creating a new issue with checklist in the body triggers checklist extraction" do
      body = <<-md
- [ ] #1
- [ ] some text
md

      issue = build(:issue, body: body, repository: @repo, user: @user)

      # no tracked issues when issue is fresh
      assert_equal issue.tracked_issues.to_a.size, 0

      issue.save!

      # tracked issues are created from extracted issues
      assert_equal issue.tracked_issues.reload.to_a.size, 1
    end

    test "creating a new issue with checklist in the body triggers checklist extraction with issue url in markdown" do
      body = <<-md
- [ ] #{@issue1.url}
- [ ] some text
md

      issue = build(:issue, body: body, repository: @repo, user: @user)

      # no tracked issues when issue is fresh
      assert_equal issue.tracked_issues.to_a.size, 0

      issue.save!

      # tracked issue is created from extracted issue
      assert_equal issue.tracked_issues.reload.to_a.size, 1
    end

    test "creating a new issue with checklist in the body triggers checklist extraction with repo nwo in markdown" do
      body = <<-md
- [ ] #{@repo.name_with_display_owner}#1
- [ ] some text
md

      issue = build(:issue, body: body, repository: @repo, user: @user)

      # no tracked issues when issue is fresh
      assert_equal issue.tracked_issues.to_a.size, 0

      issue.save!

      # tracked issue is created from extracted issue
      assert_equal issue.tracked_issues.reload.to_a.size, 1
    end

    test "creating a new issue with checklist in the body do not trigger checklist extraction when feature is disabled" do
      GitHub.flipper[:extract_checklists].disable
      body = <<-md
- [ ] #1
- [ ] some text
md

      issue = build(:issue, body: body, repository: @repo, user: @user)
      issue.save!

      # tracked issue is not created from extracted issue
      assert_equal issue.tracked_issues.reload.to_a.size, 0
    end

    test "creating a new issue with checklist with a pull request in the body does not trigger checklist extraction" do
      body = <<-md
- [ ] ##{@pr.number}
- [ ] some text
md

      issue = build(:issue, body: body, repository: @repo, user: @user)

      # no tracked issues when issue is fresh
      assert_equal issue.tracked_issues.to_a.size, 0

      issue.save!

      # tracked issue is created from extracted issue
      assert_equal issue.tracked_issues.reload.to_a.size, 0
      assert_equal issue.reload.errors.count, 0
    end

    test "updating an issue with checklist in the body triggers checklist extraction" do
      issue = create(:issue, body: "", repository: @repo, user: @user)

      body = <<-md
- [ ] #1
- [ ] some text
md
      issue.update!(body: body)

      # tracked issue is created from extracted issue
      assert_equal issue.tracked_issues.reload.to_a.size, 1
    end

    test "changing the tasks in checklist results in creation and deletion of tracked issues" do
      body = <<-md
- [ ] #1
- [ ] #2
- [ ] #3
- [ ] #4
md
      # owner-created issue
      issue = create(:issue, body: body, repository: @repo, user: @user)

      # tracked issue is created from extracted issue
      tracked_issues = issue.tracked_issues.reload
      assert_equal tracked_issues.to_a.size, 4
      assert_equal tracked_issues[0], @issue1
      assert_equal tracked_issues[1], @issue2
      assert_equal tracked_issues[2], @issue3
      assert_equal tracked_issues[3], @issue4

      new_body = <<-md
- [ ] #1
  - [ ] #3
md

      issue.update!(body: new_body)
      tracked_issues = issue.tracked_issues.reload
      assert_equal tracked_issues.to_a.size, 2
      assert_equal tracked_issues[0], @issue1
      assert_equal tracked_issues[1], @issue3
    end

    test "URLs and HTML markup get extracted correctly" do
      helper = FakeHelper.new
      helper.default_url_options = { host: "github.com" }
      url = helper.issue_url_to_main_site(@issue2)

      body = <<-md
- [ ] #1
- [ ] #{url}
<ul>
  <li>[ ] #3</li>
</ul>
md

      issue = create(:issue, body: body, repository: @repo, user: @user)

      # tracked issue is created from extracted issue
      expected_tracked_issues = Set.new([@issue1, @issue2, @issue3])
      tracked_issues = issue.tracked_issues.reload.to_set
      assert_equal tracked_issues.count, 3

      assert expected_tracked_issues.superset?(tracked_issues)
    end
  end

  context "tracked issues relation" do
    test "should delete all tracked issues if the checklist is deleted" do
      body = <<-md
- [ ] #1
- [ ] #2
md

      # owner-created issue
      issue = create(:issue, body: body, repository: @repo, user: @user)
      assert_equal 2, issue.reload.tracked_issues.to_a.size

      new_body = <<-md
md
      issue.tracked_issues.reload
      issue.update!(body: new_body)

      assert_equal 0, issue.tracked_issues.reload.to_a.size
    end

    test "should reconcile existing tracked issues" do
      issue = create(:issue, body: "", repository: @repo, user: @user)
      issue.track_issue(@issue1, @user)

      assert_equal 1, issue.tracked_issues.to_a.size
      new_body = <<-md
- [ ] #3
- [ ] #4
md
      issue.tracked_issues.reload
      issue.update!(body: new_body)

      tracked_issues = issue.tracked_issues.reload

      assert_equal 2, tracked_issues.to_a.size
      assert_equal @issue3, tracked_issues[0]
      assert_equal @issue4, tracked_issues[1]
    end

    test "should not create a tracked issue for self-mention" do
      issue = create(:issue, body: "", repository: @repo, user: @user)
      body = <<-md
- [ ] ##{issue.number}
md
      issue.update!(body: body)
      assert_equal 0, issue.tracked_issues.reload.to_a.size
    end

    test "should not create nested issues if there's a text inside task list item" do
      issue = create(:issue, body: "", repository: @repo, user: @user)
      body = <<-md
- [ ] ##{@issue1.number} some text
- [ ] ##{@issue1.number} ##{@issue2.number}
- [ ] #{@issue1.url} #{@issue2.url}
- [ ] some text ##{@issue2.number}
- [ ] ##{@issue3.number}
- [ ] #{@issue4.url}
- [ ] lalala #{@issue6.url}
- [ ] #{@issue5.url} some text
md
      issue.update!(body: body)
      assert_equal 2, issue.tracked_issues.reload.to_a.size
      assert_equal @issue3.number, issue.tracked_issues[0].number
      assert_equal @issue4.number, issue.tracked_issues[1].number
    end

    test "impersonates ghost user if both last editor and author were deleted" do
      body = <<-md
- [ ] some text
- [ ] #1

md
      issue = build(:issue, body: body, repository: @repo, user: @deleted_user)
      issue.save!

      @deleted_user.destroy
      # it resets all the cached instance variables which issue.reload won't do
      issue = Issue.find(issue.id)
      issue.body = T.must(issue.body) + "- [ ] #2"
      issue.reconcile_checklist(backfill: true)
      issue.save!

      issue.reload
      assert_equal 2, issue.source_issue_links.length
      assert_equal 2, issue.tracked_issues.length
      assert_equal User.ghost.id, T.must(issue.source_issue_links.second).actor_id
    end
  end

  context "permissions" do
    test "should not extract tracked issues if user has no access to target issues" do
      body = <<-md
- [ ] #1
- [x] #2
md

      # an issue belongs to the other user and other repo
      issue = build(:issue, body: body, user: @other)

      # no tracked issues when issue is fresh
      assert_equal issue.tracked_issues.to_a.size, 0

      issue.save!

      # tracked issue is created from extracted issue
      tracked_issues = issue.tracked_issues.reload

      # no tracked issues should be created
      assert_equal tracked_issues.to_a.size, 0
    end

    test "backfills issues if the original author and editor has lost write permissions" do
      body = <<-md
- [ ] some text
- [ ] #1

md
      member = create(:user, login: "member")
      @repo.add_member(member, action: :write)

      issue = build(:issue, body: body, repository: @repo, user: member)
      issue.save!

      @repo.remove_member(member)

      # it resets all the cached instance variables which issue.reload won't do
      issue = Issue.find(issue.id)
      issue.body = T.must(issue.body) + "- [ ] #2"
      issue.reconcile_checklist(backfill: true)
      issue.save!

      issue.reload
      assert_equal 2, issue.source_issue_links.length
      assert_equal 2, issue.tracked_issues.length
      assert_equal member.id, T.must(issue.source_issue_links.second).actor_id
    end
  end

  context "resolve_checkbox_state" do
    test "updates the checkbox of the tracked issue in a parent issue when the tracked issue is changed" do
      body = <<-md
- [ ] #1
- [ ] #1
- [ ] #1
- [ ] #2
md

      issue = create(:issue, body: body, repository: @repo, user: @user)
      perform_enqueued_jobs(only: [SyncIssueParentChecklistJob]) do
        @issue1.close(@user)
      end

      issue.reload

      closed_body = <<-md
- [x] #1
- [x] #1
- [x] #1
- [ ] #2
md

      assert_equal issue.body, closed_body

      perform_enqueued_jobs(only: [SyncIssueParentChecklistJob]) do
        @issue1.open(@user)
      end

      issue.reload

      open_body = <<-md
- [ ] #1
- [ ] #1
- [ ] #1
- [ ] #2
md

      assert_equal issue.body, open_body
    end
  end
end
