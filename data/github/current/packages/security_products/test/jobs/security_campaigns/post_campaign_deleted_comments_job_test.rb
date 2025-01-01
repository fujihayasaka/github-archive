# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsPostCampaignDeletedCommentsJobTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include DogstatsTestHelpers

  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @security_campaigns_integration = create(:campaigns_integration)

    @org = create(:organization)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)

    @issue1 = create(:issue, repository: @repo1)
    @issue2 = create(:issue, repository: @repo2)
    @issue3 = create(:issue, repository: @repo3)
    @issue_ids = [@issue1.id, @issue2.id, @issue3.id]

    @issue_for_another_campaign = create(:issue, repository: @repo1)

    @actor = create(:user, login: "einstein")
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    enable_feature_flag(:security_campaigns_issue_creation)
  end

  test "aborts if campaign issues feature flag is disabled" do
    disable_feature_flag(:security_campaigns_issue_creation)

    assert_no_changes -> { IssueComment.count } do
      assert_logged(Body: "Campaign issue comments not enabled") do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end
  end

  test "raises if integration cannot be found" do
    @security_campaigns_integration.destroy!

    assert_no_changes -> { IssueComment.count } do
      assert_raises_with_message(StandardError, "GitHub Campaigns bot not found") do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end
  end

  test "Post comments to all issues in the campaign" do
    assert_logged("gh.security_campaign.issues.comments.comments_created" => 3) do
      assert_changes -> { @issue1.comments.count }, from: 0, to: 1 do
        assert_changes -> { @issue2.comments.count }, from: 0, to: 1 do
          assert_changes -> { @issue3.comments.count }, from: 0, to: 1 do
            assert_no_changes -> { @issue_for_another_campaign.comments.count } do
              SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
            end
          end
        end
      end
    end

    expected_comment_body = "The security campaign has been deleted by [@einstein](#{UrlHelpers.user_url(@actor, host: GitHub.url)}).\n\nCheck the contact link or reach out to a campaign manager for more information.\n"

    Issue.where(id: @issue_ids).each do |issue|
      assert_equal expected_comment_body, issue.comments.first.body
    end

    assert_dogstats_increment(3, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:success"])
  end

  test "Handles when contact link isn't present" do
    assert_changes -> { @issue1.comments.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: false)
    end

    expected_comment_body = "The security campaign has been deleted by [@einstein](#{UrlHelpers.user_url(@actor, host: GitHub.url)}).\n\nReach out to a campaign manager for more information.\n"

    assert_equal expected_comment_body, @issue1.comments.first.body
  end

  test "Handles when the actor doesn't exist" do
    @actor.destroy!

    assert_changes -> { @issue1.comments.count }, from: 0, to: 1 do
      SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
    end

    expected_comment_body = "The security campaign has been deleted.\n\nCheck the contact link or reach out to a campaign manager for more information.\n"

    assert_equal expected_comment_body, @issue1.comments.first.body
  end

  test "skips issues that have been closed" do
    assert @issue1.close(@org.admin)

    assert_logged("gh.security_campaign.issues.comments.issue_closed" => 1) do
      assert_no_changes -> { @issue1.comments.count } do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_issue_closed"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:success"])
  end

  test "skips issues when the repo is archived" do
    @repo1.set_archived
    assert @repo1.reload.archived?

    assert_logged("gh.security_campaign.issues.comments.archived_repos" => 1) do
      assert_no_changes -> { @issue1.comments.count } do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_repo_archived"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:success"])
  end

  test "skips issues when the repo has disabled issues" do
    @repo1.update!(has_issues: false)

    assert_logged("gh.security_campaign.issues.comments.repos_without_issues" => 1) do
      assert_no_changes -> { @issue1.comments.count } do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(2, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:success"])
  end

  test "logs error message if issue creation fails" do
    invalid_comment = @issue1.comments.build(body: "")
    invalid_comment.save
    refute invalid_comment.persisted?

    Issue.any_instance.stubs(:create_comment).returns(invalid_comment)

    assert_logged("gh.security_campaign.issues.comments.errors" => 3) do
      assert_logged(Body: "Error posting campaign deleted issue comment") do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end

    assert_dogstats_increment(3, "security_campaign.issue.comment", tags: ["event:campaign_deleted", "status:error"])
  end

  test "no N+1 queries for archived? check" do
    # Make sure the repos hit the "async_trade_compliance_read_only?" code path.
    # Should be enough to be public and not unmaintained.
    [@repo1, @repo2, @repo3].each do |repo|
      repo.set_visibility(actor: @org.admin, visibility: Repository::PUBLIC_VISIBILITY)
    end

    assert_query_count_per_table({ "trade_controls_restrictions": 1 }) do
      SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
    end
  end

  test "ignores when an issue or a repository has been deleted" do
    @repo2.issues.each(&:destroy!)
    @repo3.destroy!

    assert_changes -> { IssueComment.count }, from: 0, to: 1 do
      assert_changes -> { @issue1.comments.count }, from: 0, to: 1 do
        SecurityCampaigns::PostCampaignDeletedCommentsJob.perform_now(deleted_campaign_id: 1234, org_id: @org.id, issue_ids: @issue_ids, actor_id: @actor.id, contact_link_present: true)
      end
    end
  end
end
