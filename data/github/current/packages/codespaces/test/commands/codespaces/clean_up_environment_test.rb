# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CleanUpEnvironmentTest < GitHub::TestCase
  include HydroTestHelpers
  include CodespacesPlanFixtures
  include GitHub::LoggerHelper

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner
    @codespace = create(:codespace)
    @codespace2 = create(:codespace, plan: @codespace.plan)
    @codespace2.name = @codespace.name
    @billing_message = build(
        :codespace_ephemeral_billing_message,
        codespace_plan_id: @codespace.plan_id,
        codespaces: [@codespace, @codespace2]
    )
    @deleted_billing_entry_guid = Faker::Internet.uuid
    @deleted_prebuild_template_guid = Faker::Internet.uuid
  end

  setup do
    GitHub.flipper[:codespaces_delete_prebuild_templates_in_environment_cleanup].disable
    FakeVSOServer.reset!
    #set up dup environments that have the same name
    FakeVSOServer.environments = [
        {
            "id" => @codespace.guid,
            "friendlyName" => @codespace.name,
            "updated" => Time.current
        },
        {
            "id" => @deleted_billing_entry_guid,
            "friendlyName" => @codespace.name,
            "updated" => Time.current
        },
        {
          "id" => @deleted_prebuild_template_guid,
          "templateStatus" => "InProgress",
          "repoId" => "123",
          "branchName" => "main",
          "devcontainerPath" => ".devcontainer/devcontainer.json",
          "isPrebuild" => true,
        }
    ]
  end

  context "#call" do
    test "deletes VSCS orphaned environment" do
      Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: @deleted_billing_entry_guid, vscs_target: :production, location: nil).call
      assert_equal 1, FakeVSOServer.environments_deleted.size
    end

    test "deletes VSCS orphaned prebuild template environment" do
      GitHub.flipper[:codespaces_delete_prebuild_templates_in_environment_cleanup].enable
      create(:codespace_prebuild_template, guid: @deleted_prebuild_template_guid)
      Codespaces::DeletePrebuildTemplatesJob.expects(:perform_later)
      Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: @deleted_prebuild_template_guid, vscs_target: :production, location: "WestUs2").call
    end

    test "does not raise error if codespace is found and is soft_deleted" do
      # mimic a soft_delete to get around having to set to deprovisioning first
      @codespace.update(deleted_at: Time.zone.now, deletion_reason: Codespace.deletion_reasons[:user_requested], state: "deprovisioned")
      Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: @codespace.guid, vscs_target: :production, location: nil).call
    end

    test "does not raise error if codespace is not found" do
      Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: "nonsense", vscs_target: :production, location: nil).call
    end

    test "raises error if codespace is found and not soft_deleted" do
      assert_raises Codespaces::CleanUpEnvironment::CodespaceFoundError do
        Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: @codespace.guid, vscs_target: :production, location: nil).call
      end
    end

    test "logs but swallows failure deleting a prebuild environment from VSCS" do
      Codespaces::VscsClient.any_instance.expects(:delete_environment).raises(Codespaces::VscsClient::BadResponseError.new("Stub", 403, Codespaces::VscsClient::PREBUILD_TEMPLATE_DELETION_DISALLOWED_ERROR_CODE))

      assert_logged(Body: "Cannot delete environment for prebuild template") do
        Codespaces::CleanUpEnvironment.new(plan_id: @codespace.plan.id, codespace_guid: "prebuild-guid", vscs_target: :production, location: nil).call
      end
    end
  end

  context "instrumentation" do
    test "instruments audit log: codespaces.deprovision_environment event" do
      events = subscribe "codespaces.deprovision_environment"

      Codespaces::CleanUpEnvironment.call(plan_id: @codespace.plan.id, codespace_guid: @deleted_billing_entry_guid, vscs_target: :production)
      expected_payload = {
        plan_id: @codespace.plan.id,
        environment_id: @deleted_billing_entry_guid,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end
end
