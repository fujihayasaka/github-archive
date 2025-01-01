# typed: true
# frozen_string_literal: true

require "test_helper"

class Billing::OpenSalesOperationsIssueTest < GitHub::TestCase
  fixtures do
    @repo = create(:repository,
                   id: Billing::OpenSalesOperationsIssue::SALES_OPS_REPO_ID,
                   owner: create(:organization, login: "github"),
                   name: "sales-operations")

    @account = create(:business)
    @title = "Test issue"
    @description = "Test issue description"
  end

  context "#valid?" do
    test "returns false and reports error if missing title" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new("", @description, @account)
      error_msg = "title and description required"

      result = issue_cmd.valid?
      report = Failbot.reports.last

      refute result
      assert_equal "ArgumentError", Failbot.exception_classname_from_hash(report)
      assert_equal error_msg, Failbot.exception_message_from_hash(report)
    end

    test "returns false and reports if missing description" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, "", @account)
      error_msg = "title and description required"
      report = Failbot.reports.last

      result = issue_cmd.valid?
      report = Failbot.reports.last


      refute result
      assert_equal "ArgumentError", Failbot.exception_classname_from_hash(report)
      assert_equal error_msg, Failbot.exception_message_from_hash(report)
    end
  end

  context "#create_or_update" do
    test "creates a new issue on the sales ops repo when one doesn't exist" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)

      assert_changes "@repo.issues.count", from: 0, to: 1 do
        issue_cmd.create_or_update
      end
    end

    test "adds a comment to existing issues" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)
      issue = @repo.issues.create(user: User.staff_user,
                                  title: @title,
                                  body: @description)

      assert_changes -> { issue.comments.count }, from: 0, to: 1 do
        issue_cmd.create_or_update
      end
    end
  end

  context "#create" do
    test "creates a new issue on the sales ops repo when one doesn't exist" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)

      assert_changes "@repo.issues.count", from: 0, to: 1 do
        issue_cmd.create
      end
    end

    test "does not add a comment to existing issues" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)
      issue = @repo.issues.create(user: User.staff_user,
                          title: @title,
                          body: @description)

      assert_no_changes -> { issue.comments.count } do
        issue_cmd.create
      end
    end
  end

  context "#body" do
    test "includes account info when provided an account" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)

      assert_match "## Account Info", issue_cmd.body
    end

    test "doesn't include account info when not provided an account" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, nil)

      refute_match "## Account Info", issue_cmd.body
    end

    test "includes footer" do
      footer = Billing::OpenSalesOperationsIssue::FOOTER

      assert_match footer, Billing::OpenSalesOperationsIssue.new(@title, @description, @account).body
    end

    test "includes stafftools link" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)
      stafftools_link_format = "https://admin.github.com/stafftools/enterprises/"
      assert_match stafftools_link_format, issue_cmd.body
    end

    test "includes zuora account link" do
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)
      zuora_link_format = "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id="

      assert_match zuora_link_format, issue_cmd.body
    end

    test "does not include zuora account link for azure accounts" do
      @account.destroy
      @account = create(:business, :with_azure_subscription)
      issue_cmd = Billing::OpenSalesOperationsIssue.new(@title, @description, @account)
      zuora_link_format = "#{GitHub.zuora_host}/apps/CustomerAccount.do?method=view&id="

      refute_match zuora_link_format, issue_cmd.body
    end
  end
end if GitHub.billing_enabled?
