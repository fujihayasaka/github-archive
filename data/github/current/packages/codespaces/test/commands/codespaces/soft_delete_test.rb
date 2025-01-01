# typed: true
# frozen_string_literal: true

require "test_helper"

module Codespaces
  class SoftDeleteTest < GitHub::TestCase
    include HydroTestHelpers

    setup do
      FakeVSOServer.reset!
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    end

    fixtures do
      @unprovisioned_codespace = create(:codespace, :unprovisioned)
      @codespace = create(:codespace)
      @codespace.deprovisioning!
      @copilot_workspace = create(:copilot_workspace)
      @copilot_workspace.deprovisioning!
    end

    test "it requires a deprovisioning codespace" do
      Codespaces::SoftDelete.call(@unprovisioned_codespace)
      refute @unprovisioned_codespace.destroyed?
    end

    test "it deletes the VSCS environment" do
      FakeVSOServer.environments = [
        {
          "id" => @codespace.guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
        }
      ]
      Codespaces::SoftDelete.call(@codespace)
      assert_includes FakeVSOServer.environments_deleted, @codespace.guid
    end

    test "it deletes has_max_idle_timeout_policy_override" do
      FakeVSOServer.environments = [
        {
          "id" => @codespace.guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
        }
      ]

      Codespaces::MaximumIdleTimeoutPolicy.set_has_override_key!(@codespace.id)
      assert Codespaces::MaximumIdleTimeoutPolicy.has_override?(@codespace.id)

      Codespaces::SoftDelete.call(@codespace)
      refute Codespaces::MaximumIdleTimeoutPolicy.has_override?(@codespace.id)
    end

    context "when the environment data guid mistmatches the ocdespace guid" do
      test "it soft deletes the codespace" do
        disable_feature_flag(:codespaces_pause_deletions_user_requested)
        environment_data = @codespace.environment_data.to_h
        environment_data["id"] = "Blorg"
        @codespace.update_attribute(:environment_data, Codespaces::Environment::Type.new.cast_value(environment_data.to_json))

        Codespaces::SoftDelete.call(@codespace, reason: "user_requested")
        refute @codespace.destroyed?
        assert @codespace.deleted?
        assert @codespace.deprovisioned?
        assert_equal "user_requested", @codespace.deletion_reason
        # Verify that calling it again does not modify `deleted_at`
        deleted = @codespace.deleted_at
        Codespaces::SoftDelete.call(@codespace)
        assert_equal deleted, @codespace.reload.deleted_at
        assert_equal 1, GitHub.dogstats.increments("codespaces_soft_delete.count", tags: ["reason:user_requested"]).count
      end
    end

    context "when the Codespace targets the local environment with a custom vscs_target_url" do
      test "it deletes the VSCS environment from the appropriate API instance" do
        codespace = create(
          :codespace,
          state: "deprovisioning",
          vscs_target_url: "https://codespaces.servicebus.windows.net/alias",
          vscs_target: :local,
        )

        stub = stub_request(:any, "https://codespaces.servicebus.windows.net/alias/api/v1/environments/#{codespace.guid}").to_return(status: 200, body: "{}")
        Codespaces::VscsClient.any_instance.stubs(:fetch_cascade_token_for_delete_or_suspend!).returns("token")

        Codespaces::SoftDelete.call(codespace)

        assert_requested :delete, /codespaces\.servicebus\.windows\.net/
      end
    end

    context "when the Codespace uses a specific location" do
      test "it deletes the VSCS environment from the appropriate location" do
        codespace = create(:codespace, state: "deprovisioning", location: "WestEurope")

        Codespaces::SoftDelete.call(codespace)

        assert_requested :delete, /westeurope\.online\.visualstudio\.com/
      end
    end

    context "when deleting the environment works" do
      test "it soft-deletes codespaces" do
        disable_feature_flag(:codespaces_pause_deletions_user_requested)
        Codespaces::SoftDelete.call(@codespace, reason: "user_requested")
        refute @codespace.destroyed?
        assert @codespace.deleted?
        assert @codespace.deprovisioned?
        assert_equal "user_requested", @codespace.deletion_reason
        # Verify that calling it again does not modify `deleted_at`
        deleted = @codespace.deleted_at
        Codespaces::SoftDelete.call(@codespace)
        assert_equal deleted, @codespace.reload.deleted_at
        assert_equal 1, GitHub.dogstats.increments("codespaces_soft_delete.count", tags: ["reason:user_requested"]).count
      end

      test "it touches the deprovisioned_at timestamp on the associated billing entry" do
        assert @codespace.billing_entry
        Codespaces::SoftDelete.call(@codespace)
        assert @codespace.billing_entry.reload.codespace_deprovisioned_at
      end
    end

    context "when deleting the environment fails" do
      test "with a 500, leaves the environment in deprovisioning" do
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@codespace.guid}",
            status: 500,
            body: "{}",
          }
        ]
        assert_raises Codespaces::Client::BadResponseError do
          Codespaces::SoftDelete.call(@codespace)
        end
        refute @codespace.destroyed?
        assert_predicate @codespace, :deprovisioning?
      end

      test "can skip vscs call - with a 500, deletes the codespace regardless of response" do
        disable_feature_flag(:codespaces_pause_deletions_user_requested)
        FakeVSOServer.fake_responses = [
          {
            endpoint: "/api/v1/environments/#{@codespace.guid}",
            status: 500,
            body: "{}",
          }
        ]

        Codespaces::SoftDelete.call(@codespace, skip_vscs: true)

        assert @codespace.deleted?
        assert @codespace.deprovisioned?
      end
    end

    context "instrumentation" do
      test "instruments audit log: codespaces.deprovision_environment event" do
        events = subscribe "codespaces.deprovision_environment"

        Codespaces::SoftDelete.call(@codespace)

        expected_payload = {
          actor: @codespace.owner.display_login,
          actor_id: @codespace.owner_id,
          codespace_id: @codespace.id,
          location: @codespace.location,
          name: @codespace.name,
          oid: @codespace.oid,
          org: nil,
          owner: @codespace.owner.login,
          owner_id: @codespace.owner.id,
          pull_request_id: nil,
          ref: @codespace.ref,
          sku_name: @codespace.sku_name,
          user_id: @codespace.owner.id,
          user: @codespace.owner.login,
          repo: @codespace.repository.nwo,
          repo_id: @codespace.repository.id,
          public_repo: @codespace.repository.public?,
          devcontainer_path: @codespace.devcontainer_path,
          machine_type: @codespace.sku&.display_name,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments audit log: codespaces.deprovision_environment with no actor when non-default deletion reason" do
        events = subscribe "codespaces.deprovision_environment"

        Codespaces::SoftDelete.call(@codespace, reason: Codespace.deletion_reasons[:stafftools_requested])

        expected_payload = {
          actor: nil,
          codespace_id: @codespace.id,
          location: @codespace.location,
          name: @codespace.name,
          oid: @codespace.oid,
          org: nil,
          owner: @codespace.owner.login,
          owner_id: @codespace.owner.id,
          pull_request_id: nil,
          ref: @codespace.ref,
          sku_name: @codespace.sku_name,
          user_id: @codespace.owner.id,
          user: @codespace.owner.login,
          repo: @codespace.repository.nwo,
          repo_id: @codespace.repository.id,
          public_repo: @codespace.repository.public?,
          devcontainer_path: @codespace.devcontainer_path,
          machine_type: @codespace.sku&.display_name,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end

      test "instruments audit log: codespaces.suspend_environment event if codespace is consuming compute" do
        events = subscribe "codespaces.suspend_environment"
        @codespace.update(environment_data: { state: Codespaces::Vscs::State::CONSUMING_COMPUTE_STATES.first })

        Codespaces::SoftDelete.call(@codespace)

        expected_payload = {
          actor: @codespace.owner.display_login,
          actor_id: @codespace.owner_id,
          codespace_id: @codespace.id,
          location: @codespace.location,
          name: @codespace.name,
          oid: @codespace.oid,
          org: nil,
          owner: @codespace.owner.login,
          owner_id: @codespace.owner.id,
          pull_request_id: nil,
          ref: @codespace.ref,
          sku_name: @codespace.sku_name,
          user_id: @codespace.owner.id,
          user: @codespace.owner.login,
          repo: @codespace.repository.nwo,
          repo_id: @codespace.repository.id,
          public_repo: @codespace.repository.public?,
          devcontainer_path: @codespace.devcontainer_path,
          machine_type: @codespace.sku&.display_name,
        }

        assert event = events.pop, "an event was expected"
        assert_equal expected_payload, event.payload
      end
    end
  end
end
