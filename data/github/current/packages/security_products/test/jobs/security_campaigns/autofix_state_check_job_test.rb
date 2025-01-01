# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsAutofixStateCheckJobTest < GitHub::TestCase
  include HydroTestHelpers

  skip_enterprise

  fixtures do
    @owner = create(:user, name: "org-owner")
    @org = create(:business_plus_organization, admin: @owner)
    @org.advanced_security_billable_entity&.mark_advanced_security_as_purchased_for_entity(actor: @owner)

    @repo1 = create(:private_repository, owner: @org, from_example: :simple)
    @repo2 = create(:private_repository, owner: @org, from_example: :simple)
    @repo3 = create(:private_repository, owner: @org, from_example: :simple)

    @campaign = create(:security_campaign, organization: @org, created_at: 5.days.ago.round)

    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 2)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo2, security_campaign: @campaign, logical_alert_number: 3)
    create(:security_campaign_alert, repository: @repo1, security_campaign: @campaign, logical_alert_number: 4)
    create(:security_campaign_alert, repository: @repo3, security_campaign: @campaign, logical_alert_number: 4)
  end

  setup do
    GitHub.flipper[:security_campaigns_disable_autofix_state_check_job].disable

    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo1).returns(true)
    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo2).returns(true)
    CodeScanning::Autofix.stubs(:any_enabled_for_repo?).with(@repo3).returns(false)
    CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "CodeQL" }.returns(true)
    CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "ESLint" }.returns(false)

    GitHub::Turboscan.stubs(:alerts_by_repo).with({
      owner_ids: [@org.id],
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
          repository_id: @repo1.id,
          number: 4,
        }),
        Turboscan::Proto::RepoNumber.new({
          number: 2,
          repository_id: @repo2.id,
        }),
        Turboscan::Proto::RepoNumber.new({
          number: 3,
          repository_id: @repo2.id,
        }),
      ],
      limit: 100,
    }).returns(
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
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 1.day).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 3,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 1.minute).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 3,
              eligible: false,
            ),
          ],
        )
      )
    )
  end

  test "does not publish event if disable feature flag is set" do
    GitHub.flipper[:security_campaigns_disable_autofix_state_check_job].enable

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)

    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
  end

  test "publishes complete event when all autofixes are complete" do
    GitHub.logger.expects(:info).with(
      "Security campaign autofixes have completed",
      "gh.organization.id" => @org.id,
      "gh.security_campaign.id" => @campaign.id,
      "gh.security_campaign.created_at" => @campaign.created_at,
      "gh.security_campaign.autofix_duration" => 86400.0,
      "gh.security_campaign.alerts_size" => 6,
      "gh.security_campaign.ineligible_repo_alerts_size" => 1,
      "gh.security_campaign.ineligible_tool_alerts_size" => 3,
      "gh.security_campaign.completed_alerts_size" => 3,
      "gh.security_campaign.autofix_state" => "complete",
    ).once

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: @campaign.id,
        number: @campaign.number,
        name: @campaign.name,
        organization_id: @campaign.organization_id,
        manager_id: @campaign.manager_id,
        due_date: @campaign.ends_at,
        created_at: @campaign.created_at,
        updated_at: @campaign.updated_at,
        closed_at: @campaign.closed_at,
      },
      duration: {
        seconds: 86400,
      },
      alerts: [
        {
          repository_id: @repo1.id,
          number: 1,
          autofix_duration: {
            seconds: 86400,
          },
          autofix_state: :AUTOFIX_STATE_SUCCESS,
        },
        {
          repository_id: @repo1.id,
          number: 3,
          autofix_duration: {
            seconds: 60,
          },
          autofix_state: :AUTOFIX_STATE_FAILED,
        },
        {
          repository_id: @repo1.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 2,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 3,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo3.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
      ],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "publishes incomplete event when some autofixes are pending" do
    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix_states_for_org).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixStatesForOrgResponse.new(
          suggested_fix_states: [
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 1,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_PENDING,
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 1.day).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 3,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 1.minute).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 3,
              eligible: false,
            ),
          ],
        )
      )
    )

    GitHub.logger.expects(:info).with(
      "Security campaign autofixes are not yet complete",
      "gh.organization.id" => @org.id,
      "gh.security_campaign.id" => @campaign.id,
      "gh.security_campaign.created_at" => @campaign.created_at,
      "gh.security_campaign.alerts_size" => 6,
      "gh.security_campaign.ineligible_repo_alerts_size" => 1,
      "gh.security_campaign.ineligible_tool_alerts_size" => 3,
      "gh.security_campaign.completed_alerts_size" => 2,
      "gh.security_campaign.incomplete_alerts_size" => 1,
      "gh.security_campaign.autofix_state" => "incomplete",
    ).once

    Timecop.freeze do
      assert_enqueued_with job: SecurityCampaigns::AutofixStateCheckJob, args: [{ campaign_id: @campaign.id }], at: 1.hour.from_now do
        SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)
      end
    end

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: @campaign.id,
        number: @campaign.number,
        name: @campaign.name,
        organization_id: @campaign.organization_id,
        manager_id: @campaign.manager_id,
        due_date: @campaign.ends_at,
        created_at: @campaign.created_at,
        updated_at: @campaign.updated_at,
        closed_at: @campaign.closed_at,
      },
      alerts: [
        {
          repository_id: @repo1.id,
          number: 1,
          autofix_duration: {
            seconds: 86400,
          },
          autofix_state: :AUTOFIX_STATE_PENDING,
        },
        {
          repository_id: @repo1.id,
          number: 3,
          autofix_duration: {
            seconds: 60,
          },
          autofix_state: :AUTOFIX_STATE_FAILED,
        },
        {
          repository_id: @repo1.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 2,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 3,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo3.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
      ],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
  end

  test "publishes event when some autofixes are pending and the campaign was created more than 14 days ago" do
    @campaign.update!(created_at: 15.days.ago.round)

    GitHub.logger.expects(:info).with(
      "Security campaign autofixes have completed",
      "gh.organization.id" => @org.id,
      "gh.security_campaign.id" => @campaign.id,
      "gh.security_campaign.created_at" => @campaign.created_at,
      "gh.security_campaign.autofix_duration" => 259200.0,
      "gh.security_campaign.alerts_size" => 6,
      "gh.security_campaign.ineligible_repo_alerts_size" => 1,
      "gh.security_campaign.ineligible_tool_alerts_size" => 3,
      "gh.security_campaign.completed_alerts_size" => 3,
      "gh.security_campaign.autofix_state" => "timed_out",
    ).once

    GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix_states_for_org).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::GetSuggestedFixStatesForOrgResponse.new(
          suggested_fix_states: [
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 1,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_PENDING,
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 2.seconds).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo1.id,
              alert_number: 3,
              eligible: true,
              state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_ERROR,
              state_updated_at: Google::Protobuf::Timestamp.new(seconds: (@campaign.created_at + 3.days).to_i),
            ),
            Turboscan::Proto::RepoSuggestedFixState.new(
              repository_id: @repo2.id,
              alert_number: 3,
              eligible: false,
            ),
          ],
        )
      )
    )

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: @campaign.id,
        number: @campaign.number,
        name: @campaign.name,
        organization_id: @campaign.organization_id,
        manager_id: @campaign.manager_id,
        due_date: @campaign.ends_at,
        created_at: @campaign.created_at,
        updated_at: @campaign.updated_at,
        closed_at: @campaign.closed_at,
      },
      duration: {
        seconds: 259_200,
      },
      alerts: [
        {
          repository_id: @repo1.id,
          number: 1,
          autofix_duration: {
            seconds: 2,
          },
          autofix_state: :AUTOFIX_STATE_TIMED_OUT,
        },
        {
          repository_id: @repo1.id,
          number: 3,
          autofix_duration: {
            seconds: 259_200,
          },
          autofix_state: :AUTOFIX_STATE_FAILED,
        },
        {
          repository_id: @repo1.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 2,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo2.id,
          number: 3,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo3.id,
          number: 4,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
      ],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "paginates with many alerts" do
    campaign = create(:security_campaign, organization: @org, created_at: 4.hours.ago.round)

    alerts = (1..322).map do |i|
      create(:security_campaign_alert, repository: @repo1, security_campaign: campaign, logical_alert_number: i)
    end

    alerts.each_slice(100) do |slice|
      GitHub::Turboscan.stubs(:alerts_by_repo).with({
        owner_ids: [@org.id],
        repo_numbers: slice.map do |alert|
          Turboscan::Proto::RepoNumber.new(
            repository_id: alert.repository_id,
            number: alert.logical_alert_number,
          )
        end,
        limit: 100,
      }).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::AlertsByRepoResponse.new(
            results: slice.map do |alert|
              Turboscan::Proto::RepoResult.new(
                repository_id: alert.repository_id,
                result: Turboscan::Proto::Result.new(
                  number: alert.logical_alert_number,
                  tool: Turboscan::Proto::ToolDescription.new(
                    name: "CodeQL",
                  ),
                ),
              )
            end,
          )
        )
      )

      GitHub::Turboscan::SuggestedFixes.stubs(:suggested_fix_states_for_org).with(
        owner_ids: [@org.id],
        filter: {
          repo_numbers: slice.map do |alert|
            Turboscan::Proto::RepoNumber.new(
              repository_id: alert.repository_id,
              number: alert.logical_alert_number,
            )
          end,
        },
        limit: 100,
      ).returns(
        Twirp::ClientResp.new(
          data: Turboscan::Proto::GetSuggestedFixStatesForOrgResponse.new(
            suggested_fix_states: slice.map do |alert|
              Turboscan::Proto::RepoSuggestedFixState.new(
                repository_id: alert.repository_id,
                alert_number: alert.logical_alert_number,
                eligible: true,
                state: Turboscan::Proto::SuggestedFixAlertState::SUGGESTED_FIX_ALERT_STATE_VALID,
                state_updated_at: Google::Protobuf::Timestamp.new(seconds: (campaign.created_at + 3.hours).to_i - alert.logical_alert_number),
              )
            end,
          )
        )
      )
    end

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: campaign.id,
        number: campaign.number,
        name: campaign.name,
        organization_id: campaign.organization_id,
        manager_id: campaign.manager_id,
        due_date: campaign.ends_at,
        created_at: campaign.created_at,
        updated_at: campaign.updated_at,
        closed_at: campaign.closed_at,
      },
      duration: {
        seconds: 10_799,
      },
      alerts: alerts.map do |alert|
        {
          repository_id: alert.repository_id,
          number: alert.logical_alert_number,
          autofix_duration: {
            seconds: 10_800 - alert.logical_alert_number,
          },
          autofix_state: :AUTOFIX_STATE_SUCCESS,
        }
      end
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "publishes event when campaign is closed" do
    @campaign.update!(closed_at: 1.day.ago)

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)

    assert_hydro_messages(count: 1, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "publishes event when there are no eligible tool alerts" do
    campaign = create(:security_campaign, organization: @org)
    create(:security_campaign_alert, repository: @repo1, security_campaign: campaign, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo3, security_campaign: campaign, logical_alert_number: 1)

    GitHub::Turboscan.stubs(:alerts_by_repo).with({
      owner_ids: [@org.id],
      repo_numbers: [
        Turboscan::Proto::RepoNumber.new({
          repository_id: @repo1.id,
          number: 1,
        }),
      ],
      limit: 100,
    }).returns(
      Twirp::ClientResp.new(
        data: Turboscan::Proto::AlertsByRepoResponse.new(
          results: [
            Turboscan::Proto::RepoResult.new(
              repository_id: @repo1.id,
              result: Turboscan::Proto::Result.new(
                number: 1,
                tool: Turboscan::Proto::ToolDescription.new(
                  name: "ESLint",
                ),
              ),
            )
          ],
        )
      )
    )

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: campaign.id,
        number: campaign.number,
        name: campaign.name,
        organization_id: campaign.organization_id,
        manager_id: campaign.manager_id,
        due_date: campaign.ends_at,
        created_at: campaign.created_at,
        updated_at: campaign.updated_at,
        closed_at: campaign.closed_at,
      },
      alerts: [
        {
          repository_id: @repo1.id,
          number: 1,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo3.id,
          number: 1,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
      ],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "publishes event when there are no eligible repo alerts" do
    campaign = create(:security_campaign, organization: @org)
    create(:security_campaign_alert, repository: @repo3, security_campaign: campaign, logical_alert_number: 1)
    create(:security_campaign_alert, repository: @repo3, security_campaign: campaign, logical_alert_number: 2)

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: campaign.id,
        number: campaign.number,
        name: campaign.name,
        organization_id: campaign.organization_id,
        manager_id: campaign.manager_id,
        due_date: campaign.ends_at,
        created_at: campaign.created_at,
        updated_at: campaign.updated_at,
        closed_at: campaign.closed_at,
      },
      alerts: [
        {
          repository_id: @repo3.id,
          number: 1,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
        {
          repository_id: @repo3.id,
          number: 2,
          autofix_state: :AUTOFIX_STATE_INELIGIBLE,
        },
      ],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "publishes event when there are no alerts in the campaign" do
    campaign = create(:security_campaign, organization: @org)

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: campaign.id)

    assert_hydro_published({
      organization: Hydro::EntitySerializer.organization(@org),
      security_campaign: {
        id: campaign.id,
        number: campaign.number,
        name: campaign.name,
        organization_id: campaign.organization_id,
        manager_id: campaign.manager_id,
        due_date: campaign.ends_at,
        created_at: campaign.created_at,
        updated_at: campaign.updated_at,
        closed_at: campaign.closed_at,
      },
      alerts: [],
    }, schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end

  test "does not fail if security campaign does not exist" do
    @campaign.destroy!

    SecurityCampaigns::AutofixStateCheckJob.perform_now(campaign_id: @campaign.id)

    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationComplete")
    refute_hydro_messages(schema: "github.security_campaigns.v0.SecurityCampaignAutofixGenerationIncomplete")
  end
end
