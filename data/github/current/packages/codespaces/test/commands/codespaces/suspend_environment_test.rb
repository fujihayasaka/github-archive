# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::SuspendEnvironmentTest < GitHub::TestCase
  include HydroTestHelpers

  setup do
    FakeVSOServer.reset!
    @user = create(:user)
    @codespace = create(:codespace)
    FakeVSOServer.environments.push({ id: @codespace.guid, state: Codespaces::Vscs::State::SHUTDOWN }.with_indifferent_access)
  end

  test "it suspends the VSCS environment" do
    assert_empty FakeVSOServer.environments_shutdown
    Codespaces::SuspendEnvironment.call(@codespace)
    assert_equal FakeVSOServer.environments_shutdown.first[:id], @codespace.guid
  end

  test "it updates the codespace's environment data" do
    refute_equal Codespaces::Vscs::State::SHUTDOWN, @codespace.environment_data.state

    Codespaces::SuspendEnvironment.call(@codespace)

    assert_equal Codespaces::Vscs::State::SHUTDOWN, @codespace.environment_data.state
  end

  test "it errors if the VSCS environment is not found" do
    FakeVSOServer.reset!

    assert_raises(Codespaces::VscsClient::BadResponseError) { Codespaces::SuspendEnvironment.call(@codespace) }
  end

  test "if we're ignoring deleted codespaces, it doesn't error if the VSCS environment is not found" do
    FakeVSOServer.reset!

    Codespaces::SuspendEnvironment.call(@codespace, ignore_deleted: true)
  end

  context "start tracking" do
    test "removes the start tracker if matching codespace" do
      start_tracker = Codespaces::PerUserStartTracker.new(@user)

      start_tracker.track_start(@codespace)
      assert Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
      Codespaces::SuspendEnvironment.call(@codespace, user: @user)
      refute Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
    end

    test "does not remove the start tracker if different codespace" do
      other_codespace = create(:codespace)
      start_tracker = Codespaces::PerUserStartTracker.new(@user)
      start_tracker.track_start(other_codespace)
      assert Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
      Codespaces::SuspendEnvironment.call(@codespace, user: @user)
      assert Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
    end

    test "does nothing if start tracker is empty" do
      start_tracker = Codespaces::PerUserStartTracker.new(@user)
      refute Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
      Codespaces::SuspendEnvironment.call(@codespace, user: @user)
      refute Codespaces::Kv.store.get(start_tracker.send(:cache_key)).value { nil }
    end
  end

  context "blocking on async operations" do
    test "it raises an exception if codespace has a pending async operation" do
      create(:codespaces_async_operation, codespace: @codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        Codespaces::SuspendEnvironment.call(@codespace)
      end
    end

    test "skips check if skip_async_oepration_check is true" do
      create(:codespaces_async_operation, codespace: @codespace)

      assert_empty FakeVSOServer.environments_shutdown
      Codespaces::SuspendEnvironment.call(@codespace, skip_async_operation_check: true)
      assert_equal FakeVSOServer.environments_shutdown.first[:id], @codespace.guid
    end
  end

  context "ending pending async operations" do
    test "it marks pending start operations as ended" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :start_codespace)

      Codespaces::SuspendEnvironment.call(@codespace)

      assert operation.reload.op_ended_at
    end

    test "leaves other pending operations alone not that this should happen" do
      operation = create(:codespaces_async_operation, codespace: @codespace, operation: :create_codespace)

      Codespaces::SuspendEnvironment.call(@codespace)
      refute operation.reload.op_ended_at
    end
  end

  context "instrumentation" do
    test "instruments audit log: codespaces.suspend_environment event" do
      events = subscribe "codespaces.suspend_environment"
      user = create(:user)
      Codespaces::SuspendEnvironment.call(@codespace, user: user)

      expected_payload = {
        actor: user.display_login,
        actor_id: user.id,
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

    test "can instrument the audit log if the owner has been deleted" do
      events = subscribe "codespaces.suspend_environment"
      user = create(:user)
      # Try to create a situation where the owner got deleted _after_ the codespace was updated in the command
      @codespace.owner.delete
      @codespace.reload
      # This will fail if the owner is gone because the codespace is invalid so we stub it out.
      @codespace.stubs(:update!).returns(true)
      Codespaces::SuspendEnvironment.call(@codespace, user: user)

      expected_payload = {
        actor: user.display_login,
        actor_id: user.id,
        codespace_id: @codespace.id,
        location: @codespace.location,
        name: @codespace.name,
        oid: @codespace.oid,
        org: nil,
        owner: nil,
        owner_id: nil,
        pull_request_id: nil,
        ref: @codespace.ref,
        sku_name: @codespace.sku_name,
        user_id: nil,
        user: nil,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
        devcontainer_path: @codespace.devcontainer_path,
        machine_type: @codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments hydro event" do
      assert_empty FakeVSOServer.environments_shutdown
      Codespaces::SuspendEnvironment.call(@codespace)

      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        actor: Hydro::EntitySerializer.user(@codespace.owner)
      }

      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceSuspend")
    end
  end

  context "vscs_client usage" do
    test "uses VscsClient.for_unscoped_management" do
      real_client = Codespaces::VscsClient.for_unscoped_deletion_or_suspension(@codespace.plan, @codespace.vscs_target)
      Codespaces::VscsClient.expects(:for_unscoped_deletion_or_suspension)
                            .with(@codespace.plan, @codespace.vscs_target, api_url: Codespaces::VscsApiUrl.for_codespace(@codespace))
                            .returns(real_client)

      Codespaces::SuspendEnvironment.call(@codespace, user: @user)
    end

    test "uses appropriate api_url for the codespaces target" do
      test_target_url = "https://codespaces.servicebus.windows.net/monalisa"
      codespace = create(:codespace, owner: @user, vscs_target: :local, vscs_target_url: test_target_url)
      cmd = Codespaces::SuspendEnvironment.new(codespace, user: @user)
      assert_equal test_target_url, cmd.send(:client).api_url
    end
  end
end
