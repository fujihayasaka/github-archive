# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::Billing::CopilotWorkspaceMessageHandlerTest < GitHub::TestCase
  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    user = create(:user)
    billable_owner = create(:codespaces_enterprise_organization)
    repository = create(:repository, owner: billable_owner)
    billable_owner.add_member(user)
    @codespace = create(:codespace, owner: user, repository: repository)
    @billing_entry = @codespace.billing_entry
    @vscs_target = "production"
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @codespace)
    @billing_entry = billing_data[:billing_entry]
    @billing_message = billing_data[:billing_message]
    @tracked_usage = billing_data[:tracked_usage]

    @cw_codespace = create(:copilot_workspace, owner: user, repository: repository)
    @cw_billing_entry = @cw_codespace.billing_entry
    billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @cw_codespace)
    @cw_billing_entry = billing_data[:billing_entry]
    @cw_billing_message = billing_data[:billing_message]
    @cw_tracked_usage = billing_data[:tracked_usage]

    @workspace_editor_cloudspace = create(:workspace_editor_cloud_environment, owner: user, repository: repository)
    @workspace_editor_billing_entry = @workspace_editor_cloudspace.billing_entry
    workspace_editor_billing_data = create_billing_data(user, vscs_target: @vscs_target, codespace: @workspace_editor_cloudspace)
    @workspace_editor_billing_entry = workspace_editor_billing_data[:billing_entry]
    @workspace_editor_billing_message = workspace_editor_billing_data[:billing_message]
    @workspace_editor_tracked_usage = workspace_editor_billing_data[:tracked_usage]
  end

  context "#perform" do
    test "returns nil if we're not dealing with a copilot workspace billing message'" do
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @billing_message, tracked_usage: @tracked_usage, billing_entry: @billing_entry).perform
    end

    test "returns nil if we're dealing with a copilot workspace storage billing message'" do
      storage_usage = @cw_billing_message.tracked_usages_for(@cw_billing_entry.codespace_guid).find(&:is_storage?)
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: storage_usage, billing_entry: @cw_billing_entry).perform
    end

    test "returns nil for an unbillable SKU" do
      @cw_tracked_usage.stubs(:sku).returns(Codespaces::Skus.sku_by_name("standardLinuxNcv3"))
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
    end

    test "returns nil if the codespace does not exist and has not been deprovisioned" do
      @cw_billing_entry.stubs(:codespace).returns(nil)
      @cw_billing_entry.stubs(:codespace_deprovisioned_at).returns(nil)
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
    end

    test "returns an appropriate result when billing billable owner is given free codespace usage because it's irrelevant to copilot workspaces" do
      GitHub.flipper[:codespaces_billing_free].enable(@cw_billing_entry.billable_owner&.billable_owner)
      result = Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
      assert result
      assert_equal Codespaces::CopilotWorkspaceBillingMessageHandlerResult, result.class
    end

    test "returns an appropriate result if the codespace does not exist and has been deprovisioned" do
      @cw_billing_entry.stubs(:codespace).returns(nil)
      @cw_billing_entry.stubs(:codespace_deprovisioned_at).returns(Time.current)
      result = Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
      assert result
      assert_equal Codespaces::CopilotWorkspaceBillingMessageHandlerResult, result.class
    end

    test "returns nil if codespace not accessible" do
      @cw_billing_entry.codespace.stubs(:accessible?).returns(false)
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
    end

    test "returns nil if billable duration isn't positive" do
      @cw_tracked_usage.stubs(:billable_duration_in_seconds).returns(0)
      refute Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
    end

    test "returns an appropriate result if we're dealing with a copilot workspace compute billing message'" do
      result = Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @cw_billing_message, tracked_usage: @cw_tracked_usage, billing_entry: @cw_billing_entry).perform
      assert result
      assert_equal Codespaces::CopilotWorkspaceBillingMessageHandlerResult, result.class
    end

    test "returns an appropriate result if we're dealing with a workspace editor cloudspace billing message" do
      result = Codespaces::Billing::CopilotWorkspaceMessageHandler.new(billing_message: @workspace_editor_billing_message, tracked_usage: @workspace_editor_tracked_usage, billing_entry: @workspace_editor_billing_entry).perform
      assert result
      assert_equal Codespaces::CopilotWorkspaceBillingMessageHandlerResult, result.class
    end
  end

  def create_billing_data(user, vscs_target: "production", codespace: create(:codespace, owner: user))
    billing_message = build(
      :codespace_ephemeral_billing_message,
      codespaces: [codespace],
      codespace_plan_id: codespace.plan.id,
      caller_name: "codespaces/dispatch_billing_message",
      vscs_target:,
    )
    billing_entry = codespace.billing_entry
    tracked_usage = billing_message.tracked_usages_for(billing_entry.codespace_guid).find(&:is_compute?)
    { billing_message:, billing_entry:, tracked_usage: }
  end
end unless GitHub.enterprise?
