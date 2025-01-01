# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesErrorReporter < GitHub::TestCase
  class MockFailbot
    attr_reader :payload, :reported, :pushed, :block_given

    def report(error, payload = {})
      @payload = payload
      @reported = true
    end

    def push(payload = {})
      @payload = payload
      @pushed = true
      # Failbot.push accepts a block so make sure we track if we were given one
      # even though we don't use it so we can verify we passed one through
      # to the underlying service.
      @block_given = block_given?
    end
  end

  fixtures do
    @codespace = create(:codespace)
  end

  setup do
    @mock_failbot = MockFailbot.new
  end

  context "push" do
    test "pushes the error to the reporting service" do
      reporter = Codespaces::ErrorReporter.new(reporter: @mock_failbot)

      reporter.push(test: "value")

      assert @mock_failbot.pushed
      assert_not @mock_failbot.reported
    end

    test "passes blocks through to the reporting service" do
      reporter = Codespaces::ErrorReporter.new(reporter: @mock_failbot)

      reporter.push(test: "value") { "BLOCK" }

      assert @mock_failbot.block_given
    end
  end

  context "report" do
    test "it reports the error to the reporting service" do
      reporter = Codespaces::ErrorReporter.new(reporter: @mock_failbot)

      reporter.report(StandardError.new("BOOM"))

      assert @mock_failbot.reported
      assert_not @mock_failbot.pushed
    end
  end

  context "Payload normalization" do
    test "it normalizes all the data properly" do
      payload = {
        codespace: @codespace
      }

      expected = {
        # Codespace data
        "gh.codespaces.id" => @codespace.id,
        "gh.codespaces.region" => @codespace.location,
        "gh.codespaces.sku_name" => @codespace.sku_name,
        "gh.codespaces.guid" => @codespace.guid,
        "gh.repo.id" => @codespace.repository_id,
        "gh.codespaces.vscs_target" => @codespace.vscs_target,
        # Plan data
        "gh.codespaces.plan.id" => @codespace.plan.id,
        "gh.codespaces.plan.name" => @codespace.plan.name,
        # Ownership data
        "gh.user.id" => @codespace.owner.id,
        "gh.user.is_staff" => false,
      }

      normalized = Codespaces::ErrorReporter::Payload.new(**payload).normalize

      assert_equal expected, normalized
    end

    test "it normalizes plan metadata when overridden" do
      plan = create(:codespace_plan, location: "SouthEastAsia")
      payload = {
        codespace: @codespace,
        plan: plan # Make sure that if we explicitly provide a plan it takes precedent over the inferred plan
      }

      expected = {
        "gh.codespaces.plan.id" => plan.id,
        "gh.codespaces.plan.name" => plan.name
      }

      normalized = Codespaces::ErrorReporter::Payload.new(**payload).normalize

      assert_subset_hash expected, normalized
    end

    test "it normalizes owner properly when overridden" do
      user = create(:user)
      payload = {
        codespace: @codespace,
        owner: user
      }

      expected = {
        "gh.user.id" => user.id
      }

      normalized = Codespaces::ErrorReporter::Payload.new(**payload).normalize

      assert_subset_hash expected, normalized
    end

    test "it normalizes organizations as owners properly" do
      org = create(:organization)
      payload = {
        codespace: @codespace,
        owner: org
      }

      expected = {
        "gh.organization.id" => org.id
      }

      normalized = Codespaces::ErrorReporter::Payload.new(**payload).normalize

      assert_subset_hash expected, normalized
    end

    test "it includes copilot_workspace_id when set" do
      copilot_workspace = create(:copilot_workspace)

      expected = {
        # Codespace data
        "gh.codespaces.id" => copilot_workspace.id,
        "gh.codespaces.region" => copilot_workspace.location,
        "gh.codespaces.sku_name" => copilot_workspace.sku_name,
        "gh.codespaces.guid" => copilot_workspace.guid,
        "gh.codespaces.copilot_workspace_id" => copilot_workspace.copilot_workspace_id,
        "gh.repo.id" => copilot_workspace.repository_id,
        "gh.codespaces.vscs_target" => copilot_workspace.vscs_target,
        # Plan data
        "gh.codespaces.plan.id" => copilot_workspace.plan.id,
        "gh.codespaces.plan.name" => copilot_workspace.plan.name,
        # Ownership data
        "gh.user.id" => copilot_workspace.owner.id,
        "gh.user.is_staff" => false,
      }

      normalized = Codespaces::ErrorReporter::Payload.new(codespace: copilot_workspace).normalize

      assert_equal expected, normalized
    end
  end
end
