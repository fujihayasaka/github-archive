# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueAlertLinkTest < GitHub::TestCase

  fixtures do

    @user = create(:user)
    @issue = create(:issue)
    @repo = create(:repository, :minimal)

  end

  context "#displayable_tracking_issues" do

    test "we get all the tracking issues for this alert that current user has permission to see" do

      issue_alert_link = create(:issue_alert_link, alert_repository: @repo, issue: @issue)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: issue_alert_link.alert_number, viewer: @user)

      assert_equal [@issue], tracking_issues

    end

    test "we do not retrieve links of same alert_number from different repos" do

      issue_alert_link = create(:issue_alert_link, alert_repository: create(:repository), issue: @issue)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: issue_alert_link.alert_number, viewer: @user)

      assert_empty tracking_issues

    end

    test "parent issues in state open are returned first" do

      issue1 = create(:issue)
      issue2 = create(:issue)
      issue3 = create(:issue)

      alert_number = 123

      create(:issue_alert_link, alert_repository: @repo, alert_number: alert_number, issue: issue1)
      create(:issue_alert_link, alert_repository: @repo, alert_number: alert_number, issue: issue2)
      create(:issue_alert_link, alert_repository: @repo, alert_number: alert_number, issue: issue3)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: alert_number, viewer: @user)

      assert_same_elements [issue1, issue2, issue3], tracking_issues

      # If issue2 is the only closed one, it should be last

      issue2.update(state: :closed)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: alert_number, viewer: @user)

      assert_same_elements [issue1, issue2, issue3], tracking_issues
      assert_equal issue2, tracking_issues.last

      # If issue3 is the only open one, it should be first

      issue1.update(state: :closed)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: alert_number, viewer: @user)

      assert_same_elements [issue1, issue2, issue3], tracking_issues
      assert_equal issue3, tracking_issues.first
    end

    test "it can handle missing issues" do
      new_issue = create(:issue)

      issue_alert_link = create(:issue_alert_link, alert_repository: @repo, issue: new_issue)

      tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: issue_alert_link.alert_number, viewer: @user)
      assert_equal [new_issue], tracking_issues

      new_issue.destroy
      issue_alert_link.reload

      assert_nothing_raised do
        tracking_issues = IssueAlertLink.displayable_tracking_issues(repository: @repo, alert_number: issue_alert_link.alert_number, viewer: @user)
      end
    end

  end
end
