# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsPostCampaignClosedCommentsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @security_campaigns_integration = create(:campaigns_integration)

    @org = create(:organization)

    @campaign = create(:security_campaign, organization: @org)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)

    @campaign_issue1 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo1)
    @campaign_issue2 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo2)
    @campaign_issue3 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo3)

    @issue_for_another_campaign = create(:security_campaign_issue, repository: @repo1)

    @actor = create(:user, login: "einstein")
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    enable_feature_flag(:security_campaigns_issue_creation)
  end

  test "aborts if campaign does not exist" do
    @campaign.destroy!

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign not present") do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end
  end

  test "aborts if campaign issues feature flag is disabled" do
    disable_feature_flag(:security_campaigns_issue_creation)

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign issue comments not enabled") do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end
  end

  test "aborts if campaign is in draft" do
    draft_campaign = create(:security_campaign, :draft, organization: @org)
    assert_no_changes -> { IssueComment.count } do
      SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: draft_campaign.id, actor_id: @actor.id)
    end
  end

  test "raises if integration cannot be found" do
    @security_campaigns_integration.destroy!

    assert_no_changes -> { IssueComment.count } do
      assert_raises_with_message(StandardError, "GitHub Campaigns bot not found") do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end
  end

  test "Post comments to all issues in the campaign" do
    assert_logged("gh.security_campaign.issues.comments.comments_created" => 3) do
      assert_changes -> { @campaign_issue1.issue.comments.count }, from: 0, to: 1 do
        assert_changes -> { @campaign_issue2.issue.comments.count }, from: 0, to: 1 do
          assert_changes -> { @campaign_issue3.issue.comments.count }, from: 0, to: 1 do
            assert_no_changes -> { @issue_for_another_campaign.issue.comments.count } do
              SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
            end
          end
        end
      end
    end

    expected_comment_body = "The security campaign has been closed by [@einstein](#{UrlHelpers.user_url(@actor, host: GitHub.url)}).\n\nCheck the contact link or reach out to a campaign manager for more information.\n"

    @campaign.issues.each do |issue|
      assert_equal expected_comment_body, issue.comments.first.body
    end

    assert_dogstats_increment(3, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success"])
  end

  test "Handles when there is no contact link" do
    @campaign.update!(contact_link: nil)

    assert_changes -> { @campaign_issue1.issue.comments.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
    end

    expected_comment_body = "The security campaign has been closed by [@einstein](#{UrlHelpers.user_url(@actor, host: GitHub.url)}).\n\nReach out to a campaign manager for more information.\n"

    assert_equal expected_comment_body, @campaign_issue1.issue.comments.first.body
  end

  test "Handles when the actor doesn't exist" do
    @actor.destroy!

    assert_changes -> { @campaign_issue1.issue.comments.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
    end

    expected_comment_body = "The security campaign has been closed.\n\nCheck the contact link or reach out to a campaign manager for more information.\n"

    assert_equal expected_comment_body, @campaign_issue1.issue.comments.first.body
  end

  test "skips issues that have been closed" do
    assert @campaign_issue1.issue.close(@org.admin)

    assert_logged("gh.security_campaign.issues.comments.issue_closed" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_issue_closed"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success"])
  end

  test "skips issues when the repo is archived" do
    @repo1.set_archived
    assert @repo1.reload.archived?

    assert_logged("gh.security_campaign.issues.comments.archived_repos" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_archived"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success"])
  end

  test "skips issues when the repo has disabled issues" do
    @campaign_issue1.repository.update!(has_issues: false)

    assert_logged("gh.security_campaign.issues.comments.repos_without_issues" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success"])
  end

  test "logs error message if issue creation fails" do
    invalid_comment = @campaign_issue1.issue.comments.build(body: "")
    invalid_comment.save
    refute invalid_comment.persisted?

    Issue.any_instance.stubs(:create_comment).returns(invalid_comment)

    assert_logged("gh.security_campaign.issues.comments.errors" => 3) do
      assert_logged(Body: "Error posting campaign closed issue comment") do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end

    assert_dogstats_increment(3, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:error"])
    assert_dogstats_increment(0, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success"])
  end

  test "no N+1 queries for archived? check" do
    # Make sure the repos hit the "async_trade_compliance_read_only?" code path.
    # Should be enough to be public and not unmaintained.
    [@repo1, @repo2, @repo3].each do |repo|
      repo.set_visibility(actor: @org.admin, visibility: Repository::PUBLIC_VISIBILITY)
    end

    assert_query_count_per_table({ "trade_controls_restrictions": 1 }) do
      SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
    end
  end

  test "ignores when an issue or a repository has been deleted" do
    @repo2.issues.each(&:destroy!)
    @repo3.destroy!

    assert_logged("gh.security_campaign.issues.comments.issue_deleted" => 1) do
      assert_logged("gh.security_campaign.issues.comments.repository_nil" => 1) do
        assert_changes -> { IssueComment.count }, from: 0, to: 1 do
          assert_changes -> { @campaign_issue1.issue.comments.count }, from: 0, to: 1 do
            SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_issue_not_found"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:skipped_repo_not_found"])
  end

  test "posts comment when issue has been transferred" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo2, actor: @org.admin)
    transfer.transfer!

    # 1 bulk query + 1 per transferred issue
    assert_query_count_per_table({ repositories: 2 }) do
      assert_changes -> { transfer.new_issue&.comments&.count }, from: 0, to: 1 do
        SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
      end
    end

    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success", "transferred:false"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success", "transferred:true"])
  end

  test "handles when issue has been transferred and original repo is deleted" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo2, actor: @org.admin)
    transfer.transfer!

    @repo1.destroy!

    assert_changes -> { transfer.new_issue&.comments&.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignClosedCommentsJob.perform_now(campaign_id: @campaign.id, actor_id: @actor.id)
    end

    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success", "transferred:false"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_closed", "status:success", "transferred:true"])
  end
end
