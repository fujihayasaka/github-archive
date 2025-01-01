# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsPostCampaignOverdueCommentsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @security_campaigns_integration = create(:campaigns_integration)

    @org = create(:organization)

    @campaign = create(:security_campaign, organization: @org, ends_at: DateTime.new(2025, 02, 05, 0, 0, 0))

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)

    @campaign_issue1 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo1)
    @campaign_issue2 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo2)
    @campaign_issue3 = create(:security_campaign_issue, security_campaign: @campaign, repository: @repo3)
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    enable_feature_flag(:security_campaigns_issue_creation)

    GitHub::Turboscan.stubs(:counts_by_repo).with({
      owner_ids: [@org.id],
      filter: {
        security_campaign_ids: [@campaign.id],
      },
    }).returns(Twirp::ClientResp.new(
      data: Turboscan::Proto::CountsByRepoResponse.new({
        open_count: 6,
        closed_count: 5,
        repository_counts: [
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo1.id,
            open_count: 5,
            closed_count: 0,
          }),
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo2.id,
            open_count: 0,
            closed_count: 4,
          }),
          Turboscan::Proto::CountsByRepoResponse::RepositoryCounts.new({
            repository_id: @repo3.id,
            open_count: 1,
            closed_count: 1,
          }),
        ],
      })
    ))
  end

  test "aborts if campaign does not exist" do
    @campaign.destroy!

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign not present") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "aborts if campaign issues feature flag is disabled" do
    disable_feature_flag(:security_campaigns_issue_creation)

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign issues not enabled") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "aborts if campaign is not overdue" do
    @campaign.update!(ends_at: 1.week.from_now)

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign not overdue") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "aborts if campaign is in draft" do
    @campaign.update!(published_at: nil, creation_query: "is:open")

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign is in draft") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "aborts if campaign is closed" do
    @campaign.update!(closed_at: 1.hour.ago)

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign closed") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "raises if integration cannot be found" do
    @security_campaigns_integration.destroy!

    assert_no_changes -> { IssueComment.count } do
      assert_raises_with_message(StandardError, "GitHub Campaigns bot not found") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "Post comments to issues in the campaign that have open alerts" do
    assert_logged("gh.security_campaign.issues.comments.comments_created" => 2) do
      assert_logged("gh.security_campaign.issues.comments.no_open_alerts" => 1) do
        assert_changes -> { @campaign_issue1.issue.comments.count }, from: 0, to: 1 do
          assert_no_changes -> { @campaign_issue2.issue.comments.count } do
            assert_changes -> { @campaign_issue3.issue.comments.count }, from: 0, to: 1 do
              SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
            end
          end
        end
      end
    end

    assert_match /This campaign was due on Feb 5, 2025\. There are currently 5 open alerts\./, @campaign_issue1.issue.comments.last.body
    assert_match /checking the contact link or asking a campaign manager to extend the due date./, @campaign_issue1.issue.comments.last.body
    assert_match /This campaign was due on Feb 5, 2025\. There is currently 1 open alert\./, @campaign_issue3.issue.comments.last.body
    assert_match /checking the contact link or asking a campaign manager to extend the due date./, @campaign_issue3.issue.comments.last.body

    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_no_open_alerts"])
  end

  test "handles when contact link is not present" do
    @campaign.update!(contact_link: nil)

    SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)

    assert_match /asking a campaign manager to extend the due date./, @campaign_issue1.issue.comments.last.body
    refute_match /contact link/, @campaign_issue1.issue.comments.last.body
  end

  test "skips issues that have been closed" do
    assert @campaign_issue1.issue.close(@org.admin)

    assert_logged("gh.security_campaign.issues.comments.issue_closed" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_issue_closed"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_no_open_alerts"])
  end

  test "skips issues when the repo is archived" do
    @repo1.set_archived

    assert_logged("gh.security_campaign.issues.comments.archived_repos" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_archived"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_no_open_alerts"])
  end

  test "skips issues when the repo has disabled issues" do
    @campaign_issue1.repository.update!(has_issues: false)

    assert_logged("gh.security_campaign.issues.comments.repos_without_issues" => 1) do
      assert_no_changes -> { @campaign_issue1.issue.comments.count } do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_no_open_alerts"])
  end

  test "logs error message if issue creation fails" do
    invalid_comment = @campaign_issue1.issue.comments.build(body: "")
    invalid_comment.save
    refute invalid_comment.persisted?

    Issue.any_instance.stubs(:create_comment).returns(invalid_comment)

    assert_logged("gh.security_campaign.issues.comments.errors" => 2) do
      assert_logged(Body: "Error posting campaign overdue issue comment") do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:error"])
    assert_dogstats_increment(0, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success"])
  end

  test "no N+1 queries for archived? check" do
    # Make sure the repos hit the "async_trade_compliance_read_only?" code path.
    # Should be enough to be public and not unmaintained.
    [@repo1, @repo2, @repo3].each do |repo|
      repo.set_visibility(actor: @org.admin, visibility: Repository::PUBLIC_VISIBILITY)
    end

    assert_query_count_per_table({ "trade_controls_restrictions": 1 }) do
      SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "ignores when an issue has been deleted" do
    @repo1.issues.each(&:destroy!)

    assert_logged("gh.security_campaign.issues.comments.issue_deleted" => 1) do
      assert_changes -> { IssueComment.count }, from: 0, to: 1 do
        assert_changes -> { @campaign_issue3.issue.comments.count }, from: 0, to: 1 do
          SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_issue_not_found"])
  end

  test "ignores when a repository has been deleted" do
    @repo1.destroy!

    assert_logged("gh.security_campaign.issues.comments.repository_nil" => 1) do
      assert_changes -> { IssueComment.count }, from: 0, to: 1 do
        assert_changes -> { @campaign_issue3.issue.comments.count }, from: 0, to: 1 do
          SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:skipped_repo_not_found"])
  end

  test "posts comment when issue has been transferred" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo3, actor: @org.admin)
    transfer.transfer!

    # 1 bulk query + 1 per transferred issue
    assert_query_count_per_table({ repositories: 2 }) do
      assert_changes -> { transfer.new_issue&.comments&.count }, from: 0, to: 1 do
        SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success", "transferred:false"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success", "transferred:true"])
  end

  test "handles when issue has been transferred and original repo is deleted" do
    transfer = IssueTransfer.new(old_issue: @campaign_issue1.issue, old_repository: @repo1, new_repository: @repo3, actor: @org.admin)
    transfer.transfer!

    @repo1.destroy!

    assert_changes -> { transfer.new_issue&.comments&.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignOverdueCommentsJob.perform_now(campaign_id: @campaign.id)
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success", "transferred:false"])
    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_overdue", "status:success", "transferred:true"])
  end
end
