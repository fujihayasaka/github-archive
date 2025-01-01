# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SecurityCampaignsGenerateAutofixesJobTest < GitHub::TestCase
  include HydroTestHelpers

  skip_enterprise

  fixtures do
    GitHub::Enterprise.ensure_business!

    @user = create(:user)
    @org = create(:organization, admin: @user)
    @campaign = create(:security_campaign, organization: @org)

    @repo1 = create(:private_repository, owner: @org, from_example: :simple)
    @repo2 = create(:private_repository, owner: @org, from_example: :simple)
  end

  setup do
    disable_feature_flag(:security_campaigns_disable)
    disable_feature_flag(:security_campaigns_disable_autofix_generation)
    codeql_tool = Turboscan::Proto::ToolDescription.new(name: "CodeQL")
    eslint_tool = Turboscan::Proto::ToolDescription.new(name: "ESLint")
    @logical_alert_info = [
      { repo_id: @repo1.id,
        alerts: [
        { alert_number: 1, tool_name: codeql_tool.name },
        { alert_number: 2, tool_name: eslint_tool.name }
      ] },
      { repo_id: @repo2.id, alerts: [{ alert_number: 3, tool_name: codeql_tool.name }] }
    ]
  end

  context "generate_autofixes" do
    test "calls turboscan to generate fixes" do
      CodeScanning::Autofix.stubs(:any_enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:any_enabled_for_repo?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).returns(true)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).with(
        user_id: @org.id,
        repository_id: @repo1.id,
        alert_numbers: [1, 2],
        ref_names_bytes: Array(@repo1.default_branch_ref.qualified_name.b),
        source: :SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
        security_campaign_id: @campaign.id
      ).once.returns(::Twirp::ClientResp.new(error: nil))

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).with(
        user_id: @org.id,
        repository_id: @repo2.id,
        alert_numbers: [3],
        ref_names_bytes: Array(@repo2.default_branch_ref.qualified_name.b),
        source: :SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
        security_campaign_id: @campaign.id
      ).once.returns(::Twirp::ClientResp.new(error: nil))

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
    end

    test "enqueues autofix state check job" do
      CodeScanning::Autofix.stubs(:any_enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:any_enabled_for_repo?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).returns(true)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).twice.returns(::Twirp::ClientResp.new(error: nil))

      assert_enqueued_with job: SecurityCampaigns::AutofixStateCheckJob, args: [{ campaign_id: @campaign.id, generate_autofix_pull_requests: false }] do
        SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
      end
    end

    test "enqueues autofix state check job when generate autofix pull requests is enabled" do
      CodeScanning::Autofix.stubs(:any_enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:any_enabled_for_repo?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).returns(true)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).twice.returns(::Twirp::ClientResp.new(error: nil))

      assert_enqueued_with job: SecurityCampaigns::AutofixStateCheckJob, args: [{ campaign_id: @campaign.id, generate_autofix_pull_requests: true }] do
        SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info, generate_autofix_pull_requests: true)
      end
    end

    test "does nothing if org has autofix disabled" do
      CodeScanning::Autofix.stubs(:enabled_for_org?).returns(false)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).never

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
    end

    test "does nothing if repos have autofix disabled" do
      CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(false)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).never

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
    end

    test "does nothing if org has campaigns autofix disabled" do
      CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(true)
      enable_feature_flag(:security_campaigns_disable_autofix_generation, @org)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).never

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
    end

    test "does nothing if campaign is in draft" do
      draft_campaign = create(:security_campaign, :draft, organization: @org)

      CodeScanning::Autofix.stubs(:enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_repo?).returns(true)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).never

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: draft_campaign.id, logical_alert_info: @logical_alert_info)
    end


    test "filters out alerts with unsupported tools" do
      CodeScanning::Autofix.stubs(:any_enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:any_enabled_for_repo?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "CodeQL" }.returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).with { |_, tool_name| tool_name == "ESLint" }.returns(false)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).with(
        user_id: @org.id,
        repository_id: @repo1.id,
        alert_numbers: [1],
        ref_names_bytes: Array(@repo1.default_branch_ref.qualified_name.b),
        source: :SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
        security_campaign_id: @campaign.id
      ).once.returns(::Twirp::ClientResp.new(error: nil))

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).with(
        user_id: @org.id,
        repository_id: @repo2.id,
        alert_numbers: [3],
        ref_names_bytes: Array(@repo2.default_branch_ref.qualified_name.b),
        source: :SUGGESTED_FIX_SOURCE_SECURITY_CAMPAIGN,
        security_campaign_id: @campaign.id
      ).once.returns(::Twirp::ClientResp.new(error: nil))

      SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
    end

    test "raises error if turboscan fails" do
      CodeScanning::Autofix.stubs(:any_enabled_for_org?).returns(true)
      CodeScanning::Autofix.stubs(:any_enabled_for_repo?).returns(true)
      CodeScanning::Autofix.stubs(:enabled_for_tool?).returns(true)

      GitHub::Turboscan::SuggestedFixes.expects(:generate_suggested_fix).once.returns(
        ::Twirp::ClientResp.new(error: "could not generate fixes"))

      assert_raises(StandardError) do
        SecurityCampaigns::GenerateAutofixesJob.perform_now(campaign_id: @campaign.id, logical_alert_info: @logical_alert_info)
      end
    end
  end
end
