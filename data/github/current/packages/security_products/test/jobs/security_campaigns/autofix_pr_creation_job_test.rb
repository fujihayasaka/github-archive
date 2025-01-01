# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsAutofixPrCreationJobTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    make_trusted_oauth_apps_owner

    @security_campaigns_integration = create(:campaigns_integration)
    @security_campaigns_bot = @security_campaigns_integration.bot
    @code_scanning_integration = create(:code_scanning_integration)

    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:private_repository, owner: @org)

    @campaign = create(:security_campaign, organization: @org, created_at: 5.days.ago.round)
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    enable_feature_flag(:security_campaigns_autofix_pr_creation)
    disable_feature_flag(:security_campaigns_disable_autofix_pr_creation_job)

    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo1).returns(true)
    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo2).returns(true)
    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo3).returns(false)
    CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "CodeQL" }.returns(true)
    CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "ESLint" }.returns(false)

    example_repo :pull_request_source, @repo1
    example_repo :pull_request_source, @repo2
    example_repo :pull_request_source, @repo3

    @repo1.heads.find("master").append_commit({
      message: "commit on default",
      committer: @owner,
    }, @owner) do |files|
      files.add("FILE_ON_MAIN", "words\nin\na\nfile\n")
    end
    @repo2.heads.find("master").append_commit({
      message: "commit on default",
      committer: @owner,
    }, @owner) do |files|
      files.add("FILE_ON_MAIN", "words\nin\na\nfile\n")
    end

    GitHub::Turboscan.stubs(:alerts_by_repo).with(
      owner_ids: [@org.id],
      security_campaign_ids: [@campaign.id],
      limit: 100,
    ).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new(
          results: [
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 1,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 3,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 4,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "ESLint",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 3,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 4,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 5,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
          ],
        )
      )
    )

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix_states_for_org).with(
      owner_ids: [@org.id],
      filter: {
        repo_numbers: [
          Turboscan::Proto::RepoNumber.new({
            repository_id: @repo1.id,
            number: 1,
          }),
          Turboscan::Proto::RepoNumber.new({
            repository_id: @repo1.id,
            number: 3,
          }),
          Turboscan::Proto::RepoNumber.new({
            number: 3,
            repository_id: @repo2.id,
          }),
          Turboscan::Proto::RepoNumber.new({
            number: 4,
            repository_id: @repo2.id,
          }),
          Turboscan::Proto::RepoNumber.new({
            number: 5,
            repository_id: @repo2.id,
          }),
        ],
      },
      limit: 100,
    ).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixStatesForOrgResponse.new(
          suggested_fix_states: [
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 1,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 3,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 3,
              eligible: false,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 4,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 5,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP,
            ),
          ],
        )
      )
    )

    GitHub::Turboscan.stubs(:get_links_for_alerts).with(
      repos_and_alerts: [
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo1.id,
          number: 1,
        }),
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo2.id,
          number: 4,
        }),
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo2.id,
          number: 5,
        }),
      ],
    ).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::GetLinksForAlertsResponse.new(
          links: [
            Turboscan::Proto::AlertLink.new(
              alert_number: 4,
              pull_request_id: 123,
              repository_id: @repo2.id
            ),
          ],
        )
      )
    )

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).with(
      repository_id: @repo1.id,
      head_commit_oid: @repo1.heads.find("master").target.oid,
      alert_numbers: [1],
      ref_names_bytes: ["refs/heads/master"],
    ).returns(
      ::Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixResponse.new(
          suggested_fix_alerts: {
            1 => Turboscan::Proto::SuggestedFixAlert.new(
              alert_number: 1,
              state: :SUGGESTED_FIX_ALERT_STATE_VALID,
              suggested_fix: Turboscan::Proto::SuggestedFix.new(
                files: [
                  Turboscan::Proto::SuggestedFixFile.new(
                    file_path: "FILE_ON_MAIN",
                    diff_content: "diff --git a/FILE_ON_MAIN b/FILE_ON_MAIN\n--- a/FILE_ON_MAIN\n+++ b/FILE_ON_MAIN\n@@ -2,3 +2,3 @@ words\n in\n-a\n+A\n file\n"
                  )
                ]
              ),
            ),
          }
        ),
        error: nil
      )
    )
    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).with(
      repository_id: @repo2.id,
      head_commit_oid: @repo2.heads.find("master").target.oid,
      alert_numbers: [5],
      ref_names_bytes: ["refs/heads/master"],
    ).returns(
      ::Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixResponse.new(
          suggested_fix_alerts: {
            5 => Turboscan::Proto::SuggestedFixAlert.new(
              alert_number: 5,
              state: :SUGGESTED_FIX_ALERT_STATE_VALID,
              suggested_fix: Turboscan::Proto::SuggestedFix.new(
                files: [
                  Turboscan::Proto::SuggestedFixFile.new(
                    file_path: "FILE_ON_MAIN",
                    diff_content: "diff --git a/FILE_ON_MAIN b/FILE_ON_MAIN\n--- a/FILE_ON_MAIN\n+++ b/FILE_ON_MAIN\n@@ -2,3 +2,3 @@ words\n in\n-a\n+A\n file\n"
                  )
                ]
              ),
            ),
          }
        ),
        error: nil
      )
    )

    ## Stubs for the new model path
    GitHub::Turboscan.stubs(:alerts_by_repo).with(
      owner_ids: [@org.id],
      security_campaign_ids: [@campaign.id],
      limit: 100,
      after_cursor: nil,
    ).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new(
          results: [
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 1,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 3,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 4,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "ESLint",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 3,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 4,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo2.id,
              result: Turboscan::Proto::Result.new(
                number: 5,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "CodeQL",
                ),
              ),
            ),
          ],
        )
      )
    )

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix_states_for_org).with(
      owner_ids: [@org.id],
      filter: { security_campaign_ids: [@campaign.id] },
      limit: 100,
      after_cursor: nil,
    ).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixStatesForOrgResponse.new(
          suggested_fix_states: [
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 1,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 3,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 3,
              eligible: false,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 4,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP,
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 5,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID_MISSING_DEP,
            ),
          ],
        )
      )
    )
  end

  test "creates PRs for autofixes" do
    assert_changes -> { @repo1.pull_requests.count }, from: 0, to: 1 do
      assert_changes -> { @repo2.pull_requests.count }, from: 0, to: 1 do
        SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: @campaign.id)
      end
    end
  end

  test "does not create PRs if the feature flag is disabled" do
    disable_feature_flag(:security_campaigns_autofix_pr_creation)

    assert_no_changes -> { PullRequest.count } do
      SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "does not create PRs if the disable feature flag is enabled" do
    enable_feature_flag(:security_campaigns_disable_autofix_pr_creation_job)

    assert_no_changes -> { PullRequest.count } do
      SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "creates PRs for autofix in workflow" do
    @repo1.heads.find("master").append_commit({
      message: "add workflow",
      committer: @owner,
    }, @owner) do |files|
      files.add(".github/workflows/my-workflow.yml", "words\nin\na\nfile\n")
    end

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).with(
      repository_id: @repo1.id,
      head_commit_oid: @repo1.heads.find("master").target.oid,
      alert_numbers: [1],
      ref_names_bytes: ["refs/heads/master"],
    ).returns(
      ::Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixResponse.new(
          suggested_fix_alerts: {
            1 => Turboscan::Proto::SuggestedFixAlert.new(
              alert_number: 1,
              state: :SUGGESTED_FIX_ALERT_STATE_VALID,
              suggested_fix: Turboscan::Proto::SuggestedFix.new(
                files: [
                  Turboscan::Proto::SuggestedFixFile.new(
                    file_path: ".github/workflows/my-workflow.yml",
                    diff_content: "diff --git a/.github/workflows/my-workflow.yml b/.github/workflows/my-workflow.yml\n--- a/.github/workflows/my-workflow.yml\n+++ b/.github/workflows/my-workflow.yml\n@@ -2,3 +2,3 @@ words\n in\n-a\n+A\n file\n"
                  )
                ]
              ),
            ),
          }
        ),
        error: nil
      )
    )

    assert_changes -> { @repo1.pull_requests.count }, from: 0, to: 1 do
      SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: @campaign.id)
    end
  end

  test "requests reviews from codeowners" do
    team = create(:team, organization: @org, privacy: :closed)
    @repo1.add_team(team, action: "write")
    @repo1.heads.find("master").append_commit({
      message: "add codeowners",
      committer: @owner,
    }, @owner) do |files|
      files.add(".github/CODEOWNERS", "* @#{@org.display_login}/#{team.slug}")
    end

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix).with(
      repository_id: @repo1.id,
      head_commit_oid: @repo1.heads.find("master").target.oid,
      alert_numbers: [1],
      ref_names_bytes: ["refs/heads/master"],
    ).returns(
      ::Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixResponse.new(
          suggested_fix_alerts: {
            1 => Turboscan::Proto::SuggestedFixAlert.new(
              alert_number: 1,
              state: :SUGGESTED_FIX_ALERT_STATE_VALID,
              suggested_fix: Turboscan::Proto::SuggestedFix.new(
                files: [
                  Turboscan::Proto::SuggestedFixFile.new(
                    file_path: "FILE_ON_MAIN",
                    diff_content: "diff --git a/FILE_ON_MAIN b/FILE_ON_MAIN\n--- a/FILE_ON_MAIN\n+++ b/FILE_ON_MAIN\n@@ -2,3 +2,3 @@ words\n in\n-a\n+A\n file\n"
                  )
                ]
              ),
            ),
          }
        ),
        error: nil
      )
    )

    GitHub.context.push(actor_id: @owner.id) do
      perform_enqueued_jobs(only: RequestPullRequestReviewersJob) do
        SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: @campaign.id)
      end
    end

    pr = T.let(@repo1.pull_requests.first, PullRequest)
    assert_equal 1, pr.events.size
    assert_equal "review_requested", pr.events.first.event
    assert_equal @security_campaigns_bot, pr.events.first.actor
    assert_equal team, pr.events.first.subject
    assert_equal 1, pr.review_requests.size
    assert_equal team, pr.review_requests.first&.reviewer
    assert_equal [true], pr.review_requests.first&.reasons&.map(&:codeowners?)
  end

  test "does not create PRs if the campaign is still in draft" do
    draft_campaign = create(:security_campaign, :draft, organization: @org)
    assert_no_changes -> { PullRequest.count } do
      SecurityCampaigns::AutofixPrCreationJob.perform_now(campaign_id: draft_campaign.id)
    end
  end
end
