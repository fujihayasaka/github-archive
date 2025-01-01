# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityCampaigns::SecurityCampaignIssueTest < GitHub::TestCase
  fixtures do
    @org = create(:organization)
    @repo = create(:repository, owner: @org)
    @issue = create(:issue, repository: @repo)
    @campaign_issue = create(:security_campaign_issue, issue: @issue, repository: @repo)
  end

  context "issue_following_transfers" do
    test "returns issue if not transferred and not deleted" do
      assert_equal @issue, @campaign_issue.issue_following_transfers
    end

    test "returns nil if issue is deleted" do
      @issue.destroy!

      assert_nil @campaign_issue.reload.issue_following_transfers
    end

    test "returns new issue if issue is transferred" do
      new_repo = create(:repository, owner: @org)

      transfer = IssueTransfer.new(old_issue: @campaign_issue.issue, old_repository: @repo, new_repository: new_repo, actor: @org.admin)
      transfer.transfer!

      refute_nil @campaign_issue.reload.issue_following_transfers
      assert_equal transfer.new_issue, @campaign_issue.reload.issue_following_transfers
    end
  end
end
