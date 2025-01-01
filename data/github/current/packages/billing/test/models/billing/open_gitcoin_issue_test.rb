# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::OpenGitcoinIssueTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository,
                   id: Billing::OpenGitcoinIssue::GITCOIN_REPO_ID,
                   owner: create(:organization, login: "github"),
                   name: "gitcoin")

    @title = "Test issue"
    @description = "Test issue description"
  end

  context "#valid?" do
    test "returns false and reports error if missing title" do
      issue_cmd = Billing::OpenGitcoinIssue.new(nil, @description)
      error_msg = "title and description required"

      result = issue_cmd.valid?
      report = Failbot.reports.last

      refute result
      assert_equal "ArgumentError", Failbot.exception_classname_from_hash(report)
      assert_equal error_msg, Failbot.exception_message_from_hash(report)
    end

    test "returns false and reports if missing description" do
      issue_cmd = Billing::OpenGitcoinIssue.new(@title, nil)
      error_msg = "title and description required"
      report = Failbot.reports.last

      result = issue_cmd.valid?
      report = Failbot.reports.last


      refute result
      assert_equal "ArgumentError", Failbot.exception_classname_from_hash(report)
      assert_equal error_msg, Failbot.exception_message_from_hash(report)
    end
  end

  context "#create" do
    test "creates a new gitcoin issue when one doesn't exist" do
      issue_cmd = Billing::OpenGitcoinIssue.new(@title, @description)

      assert_changes "@repo.issues.count", from: 0, to: 1 do
        issue_cmd.create
      end
    end

    test "doesn't create an issue when the gitcoin repo doesn't exist" do
      @repo.destroy
      issue_cmd = Billing::OpenGitcoinIssue.new(@title, @description)

      assert_no_changes "Issue.count" do
        issue_cmd.create
      end
    end
  end
end if GitHub.billing_enabled?
