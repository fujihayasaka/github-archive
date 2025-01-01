# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesProvisionEnvironmentTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers
  EnvironmentMock = Struct.new(:id, :attempted_from_prebuild, :prebuild_type)

  class FakeLock
    def initialize
      @locked = false
    end

    def locked?
      @locked
    end

    def lock!
      @locked = true
    end

    def unlock!
      @locked = false
    end
  end

  self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
  fixtures do
    make_trusted_oauth_apps_owner
    create(:codespaces_integration)

    GitHub.flipper[:codespaces_offboarding_force_limit].disable

    @monalisa = create(:credit_card_user, name: "monalisa")
    @plan = create(:codespace_plan)
    @codespace = create(:codespace, :unprovisioned, owner: @monalisa, plan: @plan)
    @provisioned_codespace = create(:codespace)
    @lock = FakeLock.new

    # Must have a non-zero spending limit to create a codespace
    create(:billing_budget, :codespaces, owner: @monalisa, enforce_spending_limit: true, spending_limit_in_subunits: 1_00)
  end

  setup do
    Codespaces::Secret.stubs(:assemble).returns([])
  end

  context "provisioning validations", skip_enterprise: true do
    test "do not call provision! if codespace is already provisioned?" do
      @provisioned_codespace.expects(:provisioning!).never
      Codespaces::ProvisionEnvironment.call(@provisioned_codespace)
    end
  end

  context "valid for provisioning" do
    test "allows `provisioning` codespaces" do
      FakeVSOServer.reset!
      provisioning = create(:codespace, :provisioning, owner: @monalisa, plan: @plan)
      Codespaces::ProvisionEnvironment.call(provisioning)
      assert_predicate provisioning, :provisioned?
    end

    test "transitions to provisioned when everything works" do
      FakeVSOServer.reset!
      Codespaces::ProvisionEnvironment.call(@codespace)
      assert_predicate @codespace, :provisioned?
    end

    test "creates the backing environment" do
      FakeVSOServer.reset!

      Codespaces::ProvisionEnvironment.call(@codespace)
      assert_equal 1, FakeVSOServer.environments_created.size
    end

    test "skips finding the environment when instructed" do
      FakeVSOServer.reset!
      Codespaces::FindEnvironment.expects(:call).never

      Codespaces::ProvisionEnvironment.call(@codespace, skip_find: true)
      assert_equal 1, FakeVSOServer.environments_created.size
    end

    test "sends the correct seed info to provision the codespace" do
      FakeVSOServer.reset!

      Codespaces::ProvisionEnvironment.call(@codespace)
      assert_equal @codespace.moniker, FakeVSOServer.environments_created.last["seed"]["moniker"]
    end

    test "sets the codespace's initial environment data" do
      FakeVSOServer.reset!

      Codespaces::ProvisionEnvironment.call(@codespace)
      assert_equal Codespaces::Vscs::State::AVAILABLE, @codespace.environment_data.state
    end

    test "returns the environment object" do
      FakeVSOServer.reset!

      env = Codespaces::ProvisionEnvironment.call(@codespace)
      assert_instance_of Codespaces::Environment, env
    end

    test "sets default idle timeout" do
      FakeVSOServer.reset!

      refute_equal 200, @codespace.environment_data.auto_shutdown_delay_minutes

      env = Codespaces::ProvisionEnvironment.call(@codespace, skip_find: true, environment_options: { autoShutdownDelayMinutes: 200 })
      assert_instance_of Codespaces::Environment, env
      assert_equal 200, env.auto_shutdown_delay_minutes
      assert_equal 200, @codespace.environment_data.auto_shutdown_delay_minutes
    end

    test "puts the codespace back to pending when there are problems" do
      FakeVSOServer.fake_responses = [
        {
          endpoint: "/api/v1/environments",
          status: 409,
          body: "2",
        }
      ]
      assert_raises Codespaces::Client::BadResponseError do
        Codespaces::ProvisionEnvironment.call(@codespace)
      end

      assert_predicate @codespace, :pending?
      assert_dogstats_increment(0, "codespaces.provisioned")
      assert_dogstats_increment(1, "codespaces/provision_environment.perform.errors")
    end
  end

  context "creation errors" do
    test "handles happy path creation errors properly" do
      FakeVSOServer.reset!
      # Pretend this first request blows up with a timeout
      Codespaces::VscsClient.any_instance.stubs(:create_environment).raises(Codespaces::Client::TimeoutError.new("BOOM!"))

      assert_raises Codespaces::CreateEnvironment::TimeoutError do
        Codespaces::ProvisionEnvironment.call(@codespace)
      end
      assert_predicate @codespace, :pending?
    end
  end

  context "instrumentation" do
    test "fires an instrumentation event", skip_enterprise: true do
      FakeVSOServer.reset!

      Codespaces::ProvisionEnvironment.call(@codespace)
      assert_predicate @codespace, :provisioned?

      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        attempted_from_prebuild: true,
        prebuild_type: nil
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceProvisioned")
      assert_dogstats_increment("codespaces.provisioned", tags: ["vscs_target:#{@codespace.vscs_target}"])
    end

    test "fires an instrumentation event with attempted_from_prebuild true" do
      attempted_prebuild_state = true
      prebuild_type = "blob"

      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
          "createFromPrebuild" => attempted_prebuild_state,
          "prebuildType" => prebuild_type
        }
      ]
      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        attempted_from_prebuild: attempted_prebuild_state,
        prebuild_type: prebuild_type
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceProvisioned")
    end

    test "fires an instrumentation event with attempted_from_prebuild false" do
      attempted_prebuild_state = false

      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
          "createFromPrebuild" => attempted_prebuild_state,
          "prebuildType" => nil
        }
      ]
      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
      message = {
        codespace: Hydro::EntitySerializer.codespace(@codespace),
        attempted_from_prebuild: attempted_prebuild_state,
        prebuild_type: nil
      }
      assert_hydro_published(message, schema: "github.codespaces.v0.CodespaceProvisioned")
    end

    test "instruments audit log: codespaces.provision_environment event" do
      events = subscribe "codespaces.provision_environment"

      Codespaces::ProvisionEnvironment.call(@codespace)
      expected_payload = {
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
        guid: @codespace.guid,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
        devcontainer_path: @codespace.devcontainer_path,
        machine_type: @codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "instruments audit log: codespaces.connect event" do
      events = subscribe "codespaces.connect"

      Codespaces::ProvisionEnvironment.call(@codespace)
      expected_payload = {
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

    test "instruments audit log: codespaces.start_environment event" do
      events = subscribe "codespaces.start_environment"

      Codespaces::ProvisionEnvironment.call(@codespace)
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

    test "fires an instrumentation event for attempted_to_create_from_prebuild when attempted_from_prebuild is true" do
      attempted_prebuild_state = true

      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
          "createFromPrebuild" => attempted_prebuild_state,
        }
      ]

      events = subscribe "codespaces.attempted_to_create_from_prebuild"

      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call

      expected_payload = {
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
        guid: @codespace.guid,
        repo: @codespace.repository.nwo,
        repo_id: @codespace.repository.id,
        public_repo: @codespace.repository.public?,
        devcontainer_path: @codespace.devcontainer_path,
        machine_type: @codespace.sku&.display_name,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not fire an instrumentation event for attempted_to_create_from_prebuild when attempted_from_prebuild is false" do
      attempted_prebuild_state = false

      events = subscribe "codespaces.attempted_to_create_from_prebuild"

      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
          "createFromPrebuild" => attempted_prebuild_state,
        }
      ]

      assert_empty events
      assert_dogstats_increment(0, "codespaces.provisioned")
    end
  end

  context "instrument event for data dog" do
    test "data dog increment for prebuild type" do
      attempted_prebuild_state = true
      prebuild_type = "CodespacePool"

      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current,
          "createFromPrebuild" => attempted_prebuild_state,
          "prebuildType" => prebuild_type
        }
      ]

      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call

      assert_equal prebuild_type, environment.prebuild_type
      assert_dogstats_increment("codespaces.prebuild_type", tags: ["prebuild_type:#{prebuild_type}"])
    end
  end

  context "metrics tags" do
    test "uses codespace's vscs_target if provided" do
      codespace = create(:codespace, vscs_target: "local", vscs_target_url: "https://codespaces.servicebus.windows.net/monalisa")

      Codespaces::ProvisionEnvironment.call(codespace)
      count = "codespaces/provision_environment.latency"
      assert_dogstats_distribution(count, tags: ["vscs_target:local"])
    end

    test "uses default vscs_target if vscs_target is not set" do
      codespace = create(:codespace)
      Codespaces::ProvisionEnvironment.call(codespace)
      count = "codespaces/provision_environment.latency"
      assert_dogstats_distribution(count, tags: ["vscs_target:#{Codespaces::Vscs.default_target}"])
    end
  end

  context "mutex behavior" do
    test "the command raises if the mutex is locked" do
      mutex = GitHub::Redis::ConcurrencySafeMutex.new("codespaces.provisioning.#{@codespace.id}", timeout: 10.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      begin
        mutex.send(:lock_with_retry)
        FakeVSOServer.reset!
        assert_raises GitHub::Redis::Mutex::LockError do
          Codespaces::ProvisionEnvironment.call(@codespace, mutex: mutex)
        end
      ensure
        mutex.unlock!
      end
    end

    test "the command unlocks the mutex normally" do
      mutex = GitHub::Redis::ConcurrencySafeMutex.new("codespaces.provisioning.#{@codespace.id}", timeout: 10.seconds, wait: 0.5.seconds, sleep: 0.1.seconds)
      FakeVSOServer.reset!
      Codespaces::ProvisionEnvironment.call(@codespace, mutex: mutex)
      refute mutex.locked?
    end
  end

  context "when locked" do
    test "returns the environment when found" do
      FakeVSOServer.reset!
      @lock.lock!

      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current
        }
      ]
      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
      assert guid, environment.id
    end

    test "raises an error when the environment cannot be found" do
      FakeVSOServer.reset!
      @lock.lock!

      assert_raises Codespaces::FindEnvironment::NotFoundError do
        Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
      end
    end
  end

  context "when unlocked" do
    test "avoids trying to find an existing environment if specified" do
      FakeVSOServer.reset!
      Codespaces::FindEnvironment.expects(:call).never
      Codespaces::CreateEnvironment.expects(:call).returns(EnvironmentMock.new(id: SecureRandom.hex(18)))
      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "", skip_find: true).call
    end

    test "returns an environment if one can be found" do
      FakeVSOServer.reset!
      guid = SecureRandom.uuid
      FakeVSOServer.environments = [
        {
          "id" => guid,
          "friendlyName" => @codespace.name,
          "updated" => Time.current
        }
      ]
      Codespaces::CreateEnvironment.expects(:call).never
      environment = Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
      assert guid, environment.id
    end

    test "attempts to create an environment when one cannot be found" do
      FakeVSOServer.reset!
      Codespaces::CreateEnvironment.expects(:call).returns(EnvironmentMock.new(id: SecureRandom.hex(18)))
      Codespaces::ProvisionEnvironment.new(@codespace, lock: @lock, github_token: "").call
    end

    test "locks itself when a timeout is raised on creation" do
      FakeVSOServer.reset!
      lock = FakeLock.new
      Codespaces::CreateEnvironment.expects(:call).raises(Codespaces::CreateEnvironment::TimeoutError.new("TIMEOUT"))
      assert_raises Codespaces::CreateEnvironment::TimeoutError do
        Codespaces::ProvisionEnvironment.new(@codespace, lock: lock, github_token: "").call
      end
      assert true, lock.locked?
    end
  end
end unless GitHub.enterprise?
