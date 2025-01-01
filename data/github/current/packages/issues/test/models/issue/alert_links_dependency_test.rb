# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueAlertLinksDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "arthurnn")
    @repo = create(:private_repository, owner: @owner)
    @user = create(:user)
    @public_repo = create(:public_repository, owner: @user, name: "public_repo")

    # make this more readable by making TrackedAlertsReconciliator available directly
    TrackedAlertsReconciliator = Issue::AlertLinksDependency::TrackedAlertsReconciliator
  end

  context "Association between Issue and Alerts" do
    test "issue_alert_links" do
      issue = create(:issue, repository: @repo, user: @owner)
      alert_42_link = create(:issue_alert_link, issue: issue, actor: @user, alert_number: 42, alert_repository: @repo)
      assert_same_elements [alert_42_link], issue.issue_alert_links
    end
  end

  context "TrackedAlertsReconciliator" do
    test "#alert_mentions in the simplest case", skip_enterprise: true do
      body = <<-md
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/12
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/42
- [ ] #{GitHub.url}/#{@public_repo.name_with_owner}/security/code-scanning/43
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      alerts = TrackedAlertsReconciliator.new(issue).alert_mentions

      assert_equal [12, 42, 43], alerts.map(&:last).sort
      assert_equal [@repo.id, @repo.id, @public_repo.id].sort, alerts.map(&:first).sort
    end

    test "#reconcile create the new linked alerts and delete old ones", skip_enterprise: true do
      body = <<-md
This is a first comment of the issue [ ] description:

- [ ] github/cybercats#100
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/1
- [ ] #{GitHub.url}/#{@public_repo.name_with_owner}/security/code-scanning/43
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/2

more text #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/3 & #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/2
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      issue.save!

      alerts = issue.issue_alert_links

      assert_equal 3, alerts.count
      assert_equal [1, 2, 43], alerts.map(&:alert_number).sort
      assert_equal [@repo.id, @repo.id, @public_repo.id].sort, alerts.map(&:alert_repository_id).sort

      issue.body = <<-md
- [ ] github/cybercats#100

more text #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/3 & #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/2
    md
      r = TrackedAlertsReconciliator.new(issue).reconcile
      assert_equal 3, r.deleted.count
      assert_empty issue.reload.issue_alert_links
    end

    test "#reconcile keeps the linked alerts if they are the same", skip_enterprise: true do
      issue = create(:issue, repository: @repo, user: @owner)
      link = create(:issue_alert_link, issue: issue, actor: @user, alert_number: 42, alert_repository: @repo)

      issue.body = <<-md
more comments

- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/42
    md

      r = TrackedAlertsReconciliator.new(issue)
      r.alert_mentions

      # Only load the linked alerts, don't create new ones nor delete old ones
      assert_query_count(1) { r.reconcile }

      assert_empty r.created
      assert_empty r.deleted

      alerts = issue.issue_alert_links
      assert_equal 1, alerts.count
      assert_equal link.id, alerts.first.id
    end

    test "#reconcile wont duplicate linked alerts if they are the same", skip_enterprise: true do
      body = <<-md
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/42
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/42
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      issue.save!

      alerts = issue.issue_alert_links
      assert_equal 1, alerts.count
      assert_equal 42, alerts.first.alert_number
    end

    test "#reconcile deletes alerts that are no longer in the issue", skip_enterprise: true do
      body = <<-md
  - [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/77
  - [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/78
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      issue.save!

      alerts = issue.issue_alert_links

      assert_equal 2, alerts.count
      assert_equal [77, 78], alerts.map(&:alert_number).sort
      assert_equal [@repo.id, @repo.id].sort, alerts.map(&:alert_repository_id).sort

      text = <<-md
  - [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/77
    md

      issue.body = text
      issue.save!

      alerts = issue.reload.issue_alert_links

      assert_equal 1, alerts.count
      assert_equal [77], alerts.map(&:alert_number).sort
      assert_equal [@repo.id].sort, alerts.map(&:alert_repository_id).sort
    end

    test "#reconcile limits", skip_enterprise: true do
      body = <<-md
  - [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/1
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      issue.save!

      assert_equal 1, issue.issue_alert_links.count

      issue.body = ((2..TrackedAlertsReconciliator::MAX_LINKS + 3).map do |i|
        "- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/#{i}"
      end).join("\n")

      r = TrackedAlertsReconciliator.new(issue).reconcile

      assert_equal TrackedAlertsReconciliator::MAX_LINKS, r.created.count
      assert_equal 1, r.deleted.count
      assert_equal TrackedAlertsReconciliator::MAX_LINKS, issue.issue_alert_links.count
    end

  end

  context "issue after_commit_hook" do
    test "#reconcile_alerts_from_body would not trigger the after_commit hook in enterprise", enterprise_only: true do
      Issue.any_instance.expects(:reconcile_alerts_from_body).never
      body = <<-md
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/42
    md

      issue = create(:issue, repository: @repo, user: @owner, body: body)
      issue.save!
    end

    test "#reconcile_alerts_from_body is called after_commit and save the new links", skip_enterprise: true do
      issue = create(:issue, repository: @repo, user: @owner)
      assert_empty issue.issue_alert_links

      issue.body = <<-md
- [ ] #{GitHub.url}/#{@repo.name_with_owner}/security/code-scanning/3
    md
      issue.save!
      assert_equal 1, issue.reload.issue_alert_links.count
    end
  end
end
