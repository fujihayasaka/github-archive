# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsUpdateIssuesJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @security_campaigns_integration = create(:campaigns_integration)
    @security_campaigns_bot = @security_campaigns_integration.bot

    @owner = create(:user, name: "org-owner")
    @org = create(:organization, admin: @owner)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)

    @campaign = create(:security_campaign, organization: @org, created_at: 5.days.ago.round)

    issue1 = create(:issue, repository: @repo1)
    issue2 = create(:issue, repository: @repo2)
    @issue3 = issue3 = create(:issue, repository: @repo3)

    @campaign_issue1 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo1, issue: issue1)
    @campaign_issue2 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo2, issue: issue2)
    @campaign_issue3 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo3, issue: issue3)

    @new_name = "new name"
    @new_description = "new description"
    @update_text = "These campaign details have been edited by the #{@security_campaigns_integration.name} bot."
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    enable_feature_flag(:security_campaigns_issue_creation)
  end

  test "updates issues for campaign" do
    @campaign.update(name: @new_name, description: @new_description)

    # 2 bulk queries + 1 per issue update
    assert_query_count_per_table({ repositories: 5 }) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_match @new_name, @campaign_issue1.issue.title
    assert_match @new_description, @campaign_issue1.issue.body
    assert_match @update_text, @campaign_issue1.issue.body
    assert_match @new_name, @campaign_issue2.issue.title
    assert_match @new_description, @campaign_issue2.issue.body
    assert_match @update_text, @campaign_issue2.issue.body
    assert_match @new_name, @campaign_issue3.issue.title
    assert_match @new_description, @campaign_issue3.issue.body
    assert_match @update_text, @campaign_issue3.issue.body
  end

  test "does not update issues when feature flag is disabled" do
    disable_feature_flag(:security_campaigns_issue_creation)

    @campaign.update(name: @new_name, description: @new_description)

    SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)

    assert_not_match @new_name, @campaign_issue1.issue.title
    assert_not_match @new_description, @campaign_issue1.issue.body
    assert_not_match @update_text, @campaign_issue1.issue.body
  end

  test "does not update issues when campaign is in draft" do
    @campaign.update(published_at: nil, creation_query: "is:open")

    SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)

    assert_not_match @new_name, @campaign_issue1.issue.title
    assert_not_match @new_description, @campaign_issue1.issue.body
    assert_not_match @update_text, @campaign_issue1.issue.body
  end

  test "does not update issues for repos without issues" do
    @campaign.update(name: @new_name, description: @new_description)
    @repo3.update(has_issues: false)

    assert_logged("gh.security_campaign.issues.repos_without_issues" => 1) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_match @new_name, @campaign_issue1.issue.title
    assert_match @new_description, @campaign_issue1.issue.body
    assert_match @update_text, @campaign_issue1.issue.body
    assert_match @new_name, @campaign_issue2.issue.title
    assert_match @new_description, @campaign_issue2.issue.body
    assert_match @update_text, @campaign_issue2.issue.body
    assert_not_match @new_name, @campaign_issue3.issue.title
    assert_not_match @new_description, @campaign_issue3.issue.body
    assert_not_match @update_text, @campaign_issue3.issue.body

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:update", "status:success"])
  end

  test "does not update issues for archived repos" do
    @campaign.update(name: @new_name, description: @new_description)
    @repo3.set_archived

    assert_logged("gh.security_campaign.issues.archived_repos" => 1) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_match @new_name, @campaign_issue1.issue.title
    assert_match @new_description, @campaign_issue1.issue.body
    assert_match @update_text, @campaign_issue1.issue.body
    assert_match @new_name, @campaign_issue2.issue.title
    assert_match @new_description, @campaign_issue2.issue.body
    assert_match @update_text, @campaign_issue2.issue.body
    assert_not_match @new_name, @campaign_issue3.issue.title
    assert_not_match @new_description, @campaign_issue3.issue.body
    assert_not_match @update_text, @campaign_issue3.issue.body

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:skipped_repo_archived"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:update", "status:success"])
  end

  test "handles deleted issues" do
    @campaign.update(name: @new_name, description: @new_description)
    @issue3.destroy

    assert_logged("gh.security_campaign.issues.issue_deleted" => 1) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_match @new_name, @campaign_issue1.issue.title
    assert_match @new_description, @campaign_issue1.issue.body
    assert_match @update_text, @campaign_issue1.issue.body
    assert_match @new_name, @campaign_issue2.issue.title
    assert_match @new_description, @campaign_issue2.issue.body
    assert_match @update_text, @campaign_issue2.issue.body
    assert_nil @campaign_issue3.issue

    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:update", "status:success"])
  end

  test "handles when repo containing issue is deleted" do
    old_name = @issue3.title
    old_description = @issue3.body
    @campaign.update(name: @new_name, description: @new_description)
    @repo3.destroy

    assert_logged("gh.security_campaign.issues.original_repo_deleted" => 1) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_match @new_name, @campaign_issue1.issue.title
    assert_match @new_description, @campaign_issue1.issue.body
    assert_match @update_text, @campaign_issue1.issue.body
    assert_match @new_name, @campaign_issue2.issue.title
    assert_match @new_description, @campaign_issue2.issue.body
    assert_match @update_text, @campaign_issue2.issue.body
    assert_match old_name, @campaign_issue3.issue.title
    assert_match old_description, @campaign_issue3.issue.body
    assert_not_match @update_text, @campaign_issue3.issue.body

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:skipped_repo_not_found"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:update", "status:success"])
  end

  test "logs after issue update" do
    @issue3.destroy
    @repo2.update(has_issues: false)

    assert_logged(Body: "Security campaign automatic issue update complete") do
      assert_logged("gh.security_campaign.issues.issues_updated" => 1) do
        assert_logged("gh.security_campaign.issues.archived_repos" => 0) do
          assert_logged("gh.security_campaign.issues.repos_without_issues" => 1) do
            assert_logged("gh.security_campaign.issues.errors" => 0) do
              SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:success", "transferred:false"])
  end

  test "logs errors when issue update fails" do
    Issues::Domain.any_instance.stubs(:update).returns(GH::Result::Error.new("custom error"))

    assert_logged("gh.security_campaign.issues.errors" => 3) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    assert_dogstats_increment(3, "security_campaign.issue", tags: ["event:update", "status:error"])
    assert_dogstats_increment(0, "security_campaign.issue", tags: ["event:update", "status:success"])
  end

  test "uses correct context for issue title update" do
    GitHub.context.push(actor_id:  @owner.id) do
      @campaign.update(name: @new_name, description: @new_description)

      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)

      assert_equal 1, @campaign_issue1.issue.events.count
      assert_equal "renamed", @campaign_issue1.issue.events.last.event
      assert_equal @security_campaigns_bot.id, @campaign_issue1.issue.events.last.actor_id
    end
  end

  test "updates issue when issue has been transferred" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo2, actor: @owner)
    transfer.transfer!

    @campaign.update(name: @new_name, description: @new_description)

    # 2 bulk queries + 1 per transferred issue + 1 per issue update
    assert_query_count_per_table({ repositories: 6 }) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    transfer.reload
    assert_match @new_name, transfer.new_issue&.title
    assert_match @new_description, transfer.new_issue&.body
    assert_match @update_text, transfer.new_issue&.body

    # Should link to the original repo
    campaign_repo_path = UrlHelpers.repository_security_campaign_path(repository: @repo1, user_id: @org.display_login, number: @campaign.number)
    assert_match campaign_repo_path, transfer.new_issue&.body

    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:update", "status:success", "transferred:false"])
    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:success", "transferred:true"])
  end

  test "handles when issue has been transferred and original repo is deleted" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo2, actor: @owner)
    transfer.transfer!

    @repo1.destroy!

    @campaign.update(name: @new_name, description: @new_description)

    assert_logged("gh.security_campaign.issues.original_repo_deleted" => 1) do
      SecurityCampaigns::UpdateIssuesJob.perform_now(campaign_id: @campaign.id)
    end

    transfer.reload
    refute_match @new_name, transfer.new_issue&.title

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:update", "status:skipped_repo_not_found"])
  end
end
