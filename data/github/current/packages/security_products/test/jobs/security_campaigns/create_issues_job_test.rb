# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsCreateIssuesJobTest < GitHub::TestCase
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
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
  end

  test "creates issues for campaign" do
    assert_changes -> { SecurityCampaigns::SecurityCampaignIssue.count }, from: 0, to: 3 do
      assert_changes -> { @repo1.issues.count }, from: 0, to: 1 do
        assert_changes -> { @repo2.issues.count }, from: 0, to: 1 do
          assert_changes -> { @repo3.issues.count }, from: 0, to: 1 do
            SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
          end
        end
      end
    end
  end

  test "does not create issues for repos without issues" do
    @repo3.update(has_issues: false)

    assert_logged("gh.security_campaign.issues.repos_without_issues" => 1) do
      assert_changes -> { SecurityCampaigns::SecurityCampaignIssue.count }, from: 0, to: 2 do
        assert_changes -> { @repo1.issues.count }, from: 0, to: 1 do
          assert_changes -> { @repo2.issues.count }, from: 0, to: 1 do
            assert_no_changes -> { @repo3.issues.count } do
              SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:create", "status:success"])
  end

  test "does not create issues for archived repos" do
    @repo3.set_archived

    assert_logged("gh.security_campaign.issues.archived_repos" => 1) do
      assert_changes -> { SecurityCampaigns::SecurityCampaignIssue.count }, from: 0, to: 2 do
        assert_changes -> { @repo1.issues.count }, from: 0, to: 1 do
          assert_changes -> { @repo2.issues.count }, from: 0, to: 1 do
            assert_no_changes -> { @repo3.issues.count } do
              SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:skipped_repo_archived"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:create", "status:success"])
  end

  test "logs after issue creation" do
    @repo3.set_archived
    @repo2.update(has_issues: false)

    assert_logged(Body: "Security campaign automatic issue creation complete") do
      assert_logged("gh.security_campaign.issues.issues_created" => 1) do
        assert_logged("gh.security_campaign.issues.archived_repos" => 1) do
          assert_logged("gh.security_campaign.issues.repos_without_issues" => 1) do
            assert_logged("gh.security_campaign.issues.errors" => 0) do
              SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:skipped_repo_has_issues"])
    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:skipped_repo_archived"])
    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:success"])
  end

  test "skips cases where the issue already exists" do
    create(:security_campaign_issue, security_campaign: @campaign, repository: @repo3)

    assert_logged("gh.security_campaign.issues.issue_already_exists" => 1) do
      assert_changes -> { @campaign.issues.count }, from: 1, to: 3 do
        assert_changes -> { @repo1.issues.count }, from: 0, to: 1 do
          assert_changes -> { @repo2.issues.count }, from: 0, to: 1 do
            assert_no_changes -> { @repo3.issues.count } do
              SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:skipped_issue_already_exists"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:create", "status:success"])
  end

  test "catches and reports ActiveRecord::RecordNotUnique errors" do
    # Pretend the issue doesn't exist so we can test the error
    create(:security_campaign_issue, security_campaign: @campaign, repository: @repo3)
    SecurityCampaigns::SecurityCampaignIssue.stubs(:exists?).returns(false)

    assert_logged(Body: "ActiveRecord::RecordNotUnique error when creating security campaign issue") do
      assert_logged("gh.security_campaign.issues.record_not_unique" => 1) do
        assert_changes -> { @campaign.issues.count }, from: 1, to: 3 do
          assert_changes -> { @repo1.issues.count }, from: 0, to: 1 do
            assert_changes -> { @repo2.issues.count }, from: 0, to: 1 do
              # It's not ideal but we still create an extra issue, but it doesn't get linked to the campaign
              assert_changes -> { @repo3.issues.count }, from: 1, to: 2 do
                SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
              end
            end
          end
        end
      end
    end

    assert_dogstats_increment(1, "security_campaign.issue", tags: ["event:create", "status:error_record_not_unique"])
    assert_dogstats_increment(2, "security_campaign.issue", tags: ["event:create", "status:success"])
  end

  test "job is idempotent and does not create duplicate issues" do
    assert_changes -> { @campaign.issues.count }, from: 0, to: 3 do
      assert_changes -> { Issue.count }, from: 0, to: 3 do
        SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
      end
    end

    assert_no_changes -> { @campaign.issues.count } do
      assert_no_changes -> { Issue.count } do
        SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
      end
    end
  end

  test "does not create issues for draft campaign" do
    draft_campaign = create(:security_campaign, :draft, organization: @org)

    assert_no_changes -> { SecurityCampaigns::SecurityCampaignIssue.count } do
      assert_no_changes -> { Issue.count } do
        SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: draft_campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
      end
    end
  end

  test "creates issues for campaign when content creation rate limit is enabled" do
    enable_content_creation_rate_limiting

    assert_changes -> { SecurityCampaigns::SecurityCampaignIssue.count }, from: 0, to: 3 do
      SecurityCampaigns::CreateIssuesJob.perform_now(campaign_id: @campaign.id, repository_ids: [@repo1.id, @repo2.id, @repo3.id])
    end
  end
end
