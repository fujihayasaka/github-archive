# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class RestoreTest < GitHub::TestCase
    include HydroTestHelpers

    setup do
      FakeVSOServer.reset!
    end

    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @user = create(:user)

      @deleted_codespace = create(:codespace, owner: @user, billable_owner: @user, deleted_at: Time.current, shutdown_at: Time.current)
      @deleted_codespace.deprovisioned!

      @codespace = create(:codespace, owner: @user, billable_owner: @user)
      @codespace.deprovisioning!

      @deleted_env = {
        "id" => @deleted_codespace.guid,
        "friendlyName" => @deleted_codespace.name,
        "updated" => Time.current,
      }
    end

    test "it requires a deleted codespace" do
      refute @codespace.deleted?
      Codespaces::Restore.call(@codespace)
      # nothing happens
      refute @codespace.deleted?

      assert @deleted_codespace.deleted?
      FakeVSOServer.environments = [@deleted_env]
      Codespaces::Restore.call(@deleted_codespace)
      # restored, deleted_at has been cleared
      refute @deleted_codespace.deleted?
    end

    test "it requires a restorable codespace" do
      @deleted_codespace.deprovision!
      refute @deleted_codespace.restorable?
      Codespaces::Restore.call(@codespace)
      # nothing happens
      assert @deleted_codespace.deleted?
    end

    test "it requires a accessible codespace" do
      @deleted_codespace.repository.destroy
      assert @deleted_codespace.restorable?
      refute @deleted_codespace.accessible?
      Codespaces::Restore.call(@codespace)
      # nothing happens
      assert @deleted_codespace.deleted?
    end

    test "it restores the VSCS environment and codespace" do
      restored_at = Time.current

      @deleted_env["last_state_update_reason"] = "restore"
      FakeVSOServer.environments = [@deleted_env]
      Codespaces::Restore.call(@deleted_codespace)
      assert_includes FakeVSOServer.environments_restored, @deleted_codespace.guid

      refute @deleted_codespace.deleted?
      assert_nil @deleted_codespace.shutdown_at

      message = {
        codespace: Hydro::EntitySerializer.codespace(@deleted_codespace),
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceRestored")
      assert_equal "restore", @deleted_codespace.environment_data.last_state_update_reason
    end

    test "it restores has_max_idle_timeout_policy_override" do
      FakeVSOServer.environments = [
        {
          "id" => @deleted_codespace.guid,
          "friendlyName" => @deleted_codespace.name,
          "updated" => Time.current,
        }
      ]

      refute Codespaces::MaximumIdleTimeoutPolicy.has_override?(@deleted_codespace.id)

      Codespaces::Restore.call(@deleted_codespace)
      assert Codespaces::MaximumIdleTimeoutPolicy.has_override?(@deleted_codespace.id)
    end

    context "when the Codespace targets the local environment with a custom vscs_target_url" do
      test "it restores the VSCS environment from the appropriate API instance" do
        codespace = create(
          :codespace,
          owner: @user,
          billable_owner: @user,
          state: "deprovisioned",
          deleted_at: Time.current,
          vscs_target_url: "https://codespaces.servicebus.windows.net/",
          vscs_target: :local,
        )

        FakeVSOServer.environments = [
          {
            "id" => codespace.guid,
            "friendlyName" => codespace.name,
            "updated" => Time.current,
          }
        ]

        stub = stub_request(:any, ->(uri) { uri.host == "codespaces.servicebus.windows.net" }).to_rack(FakeVSOServer)

        Codespaces::Restore.call(codespace)

        assert_requested :patch, /codespaces\.servicebus\.windows\.net/
      end
    end

    context "when the Codespace uses a specific location" do
      test "it restores the VSCS environment from the appropriate location" do
        codespace = create(:codespace, owner: @user, billable_owner: @user, deleted_at: Time.current, location: "WestEurope")
        codespace.deprovisioned!

        FakeVSOServer.environments = [{
          "id" => codespace.guid,
          "friendlyName" => codespace.name,
          "updated" => Time.current,
        }]
        Codespaces::Restore.call(codespace)

        assert_requested :patch, /westeurope\.online\.visualstudio\.com/
      end
    end

    test "it does not try to restore the environment when the codespace is not deleted" do
      Codespaces::Restore.call(@codespace)

      refute_includes FakeVSOServer.environments_restored, @codespace.guid
      refute @codespace.deleted?
    end

    context "when restoring the environment works" do
      test "it restores provisioned codespace" do
        assert @deleted_codespace.deleted?
        assert @deleted_codespace.deprovisioned?

        events = subscribe "codespaces.restore"

        FakeVSOServer.environments = [@deleted_env]
        Codespaces::Restore.call(@deleted_codespace)

        refute @deleted_codespace.deleted?
        assert @deleted_codespace.provisioned?

        assert event = events.pop, "an event was expected"
      end

      test "it creates a new billing entry" do
        disable_feature_flag(:codespaces_pause_deletions_user_requested)
        FakeVSOServer.environments = [
          {
            "id" => @codespace.guid,
            "friendlyName" => @codespace.name,
            "updated" => Time.current,
         }
        ]

        Codespaces::SoftDelete.call(@codespace)

        initial_billing_entry = @codespace.reload.billing_entry
        assert initial_billing_entry.codespace_deprovisioned_at.present?

        Codespaces::Restore.call(@codespace)

        assert latest_billing_entry = @codespace.reload.billing_entry
        refute @codespace.billing_entry.codespace_deprovisioned_at.present?

        refute_equal initial_billing_entry.id, latest_billing_entry.id
      end

      test "it stores copilot_workspace_id on newly created billing entry" do
        disable_feature_flag(:codespaces_pause_deletions_user_requested)
        deleted_cw = create(:copilot_workspace, owner: @user, billable_owner: @user, deleted_at: Time.current, shutdown_at: Time.current)
        deleted_cw.deprovisioned!

        FakeVSOServer.environments = [
          {
            "id" => deleted_cw.guid,
            "friendlyName" => deleted_cw.name,
            "updated" => Time.current,
         }
        ]

        Codespaces::Restore.call(deleted_cw)

        refute deleted_cw.billing_entry.codespace_deprovisioned_at.present?
        assert deleted_cw.billing_entry.copilot_workspace_id.present?
      end
    end

    context "when restoring the environment fails" do
      test "with a 500, leaves the environment in deprovisioning" do
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@deleted_codespace.guid}/restore",
            status: 500,
            body: "{}",
          }
        ]
        assert_raises Codespaces::Client::BadResponseError do
          Codespaces::Restore.call(@deleted_codespace)
        end
        assert @deleted_codespace.deleted?
        refute_predicate @deleted_codespace, :provisioned?
      end

      test "when the environment is not found, raises InvalidEnv error and does not restore codespace" do
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@deleted_codespace.guid}/restore",
            status: 404,
            body: "{}",
          }
        ]
        assert_raises Codespaces::Restore::InvalidEnv do
          Codespaces::Restore.call(@deleted_codespace)
        end
        assert @deleted_codespace.deleted?
      end
    end

    context "instrumentation" do
      test "instruments audit log and hydro events" do
        events = subscribe "codespaces.restore"

        FakeVSOServer.environments = [@deleted_env]

        Codespaces::Restore.call(@deleted_codespace)

        expected_payload = {
          owner_id: @deleted_codespace.owner.id,
          owner: @deleted_codespace.owner.login,
          codespace_id: @deleted_codespace.id,
          plan_id: @deleted_codespace.plan.id,
          environment_id: @deleted_codespace.guid,
          repo: @deleted_codespace.repository.nwo,
          repo_id: @deleted_codespace.repository.id,
          public_repo: @deleted_codespace.repository.public?,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload

        assert_hydro_published({ codespace: Hydro::EntitySerializer.codespace(@deleted_codespace) }, schema: "github.codespaces.v0.CodespaceRestored")
      end
    end
  end
end
