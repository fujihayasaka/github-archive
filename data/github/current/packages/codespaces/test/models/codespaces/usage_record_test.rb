# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesUsageRecordTest < GitHub::TestCase
  context "#current" do
    test "includes usage in the current month" do
      usage = create(:codespace_usage_record)
      assert Codespaces::UsageRecord.current.include?(usage)
    end

    test "excludes usage in previous months" do
      usage = create(:codespace_usage_record, start_at: DateTime.current.beginning_of_month - 1.hour, end_at: DateTime.current.beginning_of_month)
      refute Codespaces::UsageRecord.current.include?(usage)
    end
  end

  context "#for_workspace_editor" do
    test "includes usage records for copilot workspaces" do
      usage = create(:codespace_usage_record, :for_workspace_editor_cloud_environment)
      assert Codespaces::UsageRecord.for_workspace_editor.include?(usage)
    end

    test "excludes usage records for normal codespaces" do
      usage = create(:codespace_usage_record)
      refute Codespaces::UsageRecord.for_workspace_editor.include?(usage)
    end

    test "excludes usage records for workspace editor codespaces" do
      usage = create(:codespace_usage_record, :for_copilot_workspace)
      refute Codespaces::UsageRecord.for_workspace_editor.include?(usage)
    end
  end

  context "#for_copilot_workspaces" do
    test "includes usage records for copilot workspaces" do
      usage = create(:codespace_usage_record, :for_copilot_workspace)
      assert Codespaces::UsageRecord.for_copilot_workspaces.include?(usage)
    end

    test "excludes usage records for normal codespaces" do
      usage = create(:codespace_usage_record)
      refute Codespaces::UsageRecord.for_copilot_workspaces.include?(usage)
    end

    test "excludes usage records for workspace editor codespaces" do
      usage = create(:codespace_usage_record, :for_workspace_editor_cloud_environment)
      refute Codespaces::UsageRecord.for_copilot_workspaces.include?(usage)
    end
  end
end
