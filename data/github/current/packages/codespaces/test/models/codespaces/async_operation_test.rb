# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesAsyncOperationTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @codespace = create(:codespace)
  end

  setup do
    GitHub.context.push(request_id: "1234")
    GitHub.flipper[:codespaces_automated_testing].disable
  end

  context "#check_if_complete" do
    test "returns true if the operation is complete" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      operation = create(:codespaces_async_operation, :started, codespace: codespace)

      assert codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      assert_equal true, operation.check_if_complete
    end

    test "returns false if the operation is not complete" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      operation = create(:codespaces_async_operation, :started, codespace: codespace)

      assert codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      assert_equal false, operation.check_if_complete
    end

    test "returns false if the operation doesn't have a codespace" do
      operation = create(:codespaces_async_operation, codespace: nil, operation: :create_codespace)
      assert_equal false, operation.check_if_complete
    end

    test "returns false if forcing update and codespace has no guid yet" do
      codespace = create(:codespace, :provisioning)
      operation = create(:codespaces_async_operation, :started, operation: :create_codespace, codespace: codespace)
      Codespaces::VscsClient.any_instance.expects(:fetch_environment!).never
      assert_equal false, operation.check_if_complete(force_update: true)
    end

    test "returns false if forcing update and the codespace owner has been deleted" do
      operation = create(:codespaces_async_operation, :started, operation: :create_codespace)
      operation.codespace.owner.delete
      operation.reload
      Codespaces::VscsClient.any_instance.expects(:fetch_environment!).never
      assert_equal false, operation.check_if_complete(force_update: true)
    end

    test "returns false if forcing update and the API call blows up" do
      operation = create(:codespaces_async_operation, :started, operation: :create_codespace)
      Codespaces::VscsClient.any_instance.expects(:fetch_environment!).raises(Codespaces::VscsClient::BadResponseError.new("BadResponse"))
      assert_equal false, operation.check_if_complete(force_update: true)
    end

    test "returns false if the environment's updated timestamp is before the operation was started" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      operation = create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)

      assert codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => (operation.op_started_at - 1.second).iso8601,
      })

      assert_equal false, operation.check_if_complete
    end
  end

  context "#check_for_completed_operations" do
    test "does nothing if codespace doesn't have async ops" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)

      refute codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      refute codespace.pending_async_operations.any?
    end

    test "does nothing if codespace only has completed ops" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :finished, codespace: codespace)

      refute codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      refute codespace.pending_async_operations.any?
    end

    test "completes operation when it gets the correct state and env reflects changed sku" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :started, codespace: codespace)

      assert codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      refute codespace.pending_async_operations.any?
    end

    test "completes operation when processing a possibly stale payload from the background job" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :started, codespace: codespace)

      assert codespace.pending_async_operations.any?

      # Pretend we already processed this one and set it on the codespace
      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      # But then this one comes in from a retry or network delay - op started 1 minute ago by default in the factory
      stale_environment = Codespaces::Environment.from_json({
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => 1.second.ago.iso8601,
        "skuName" => "standardLinux",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace, env: stale_environment)

      refute codespace.pending_async_operations.any?
    end

    test "checks multiple different pending operations and completes them when it gets the correct state and env reflects changed sku" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)
      create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)

      assert codespace.pending_async_operations.many?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      refute codespace.pending_async_operations.any?
    end

    test "completes operation for soft deleted codespace when it gets the correct state and env reflects changed sku" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :started, codespace: codespace)
      assert codespace.pending_async_operations.any?
      Codespaces::AsyncOperation.any_instance.expects(:report_operation).with(completion_state: Codespaces::AsyncOperation::State::ENDED, failure_reason: nil, caller: nil)

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      codespace.deprovision!
      Codespaces::SoftDelete.call(codespace)

      ops = Codespaces::AsyncOperation.all
      ops.each do |op|
        assert op.check_if_complete
      end

      refute codespace.pending_async_operations.any?
    end

    test "completes operation and considers it succeeded when it gets the correct state when completion state" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)
      assert codespace.pending_async_operations.any?
      Codespaces::AsyncOperation.any_instance.expects(:report_operation).with(completion_state: Codespaces::AsyncOperation::State::SUCCEEDED, failure_reason: nil, caller: nil)

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::AVAILABLE,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      codespace.deprovision!
      Codespaces::SoftDelete.call(codespace)

      ops = Codespaces::AsyncOperation.all
      ops.each do |op|
        assert op.check_if_complete
      end

      refute codespace.pending_async_operations.any?
    end

    test "completes operation and considers it failed when it gets the correct state when completion state" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)
      assert codespace.pending_async_operations.any?
      Codespaces::AsyncOperation.any_instance.expects(:report_operation).with(completion_state: Codespaces::AsyncOperation::State::FAILED, failure_reason: nil, caller: nil)

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "standardLinux",
      })

      codespace.deprovision!
      Codespaces::SoftDelete.call(codespace)

      ops = Codespaces::AsyncOperation.all
      ops.each do |op|
        assert op.check_if_complete
      end

      refute codespace.pending_async_operations.any?
    end

    test "doesn't complete operation when state is correct, but env reflects no change in sku" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      create(:codespaces_async_operation, codespace: codespace)

      assert codespace.pending_async_operations.any?

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => Time.now.iso8601,
        "skuName" => "basicLinux32gb",
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      assert codespace.pending_async_operations.any?
    end

    test "doesn't complete operation when environment data is before the operation was started" do
      codespace = create(:codespace, sku_name: :basicLinux32gb)
      op = create(:codespaces_async_operation, :started, codespace: codespace, operation: :start_codespace)

      codespace.update_attribute(:environment_data, {
        "id" => codespace.guid,
        "state" => Codespaces::Vscs::State::SHUTDOWN,
        "updated" => (op.op_started_at - 1.second).iso8601,
      })

      Codespaces::AsyncOperation.check_for_completed_operations(codespace)

      refute op.reload.op_ended_at
    end
  end

  context "metrics and logging" do
    test "logs and increments on creation" do
      codespace = create(:codespace)
      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", has_entries(
        "gh.codespaces.async_operation.id" => anything,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.async_operation.state" => "requested",
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Codespaces::AsyncOperation.create(operation: 0, codespace: codespace)
      assert_dogstats_increment(1, "codespaces.async_operations.requested", tags: ["operation:update_storage", "state:requested"])
    end

    test "logs and increments on creation with a nil codespace" do
      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", has_entries(
        "gh.codespaces.async_operation.id" => anything,
        "gh.codespaces.async_operation.name" => "create_codespace",
        "gh.codespaces.async_operation.state" => "requested",
        "gh.codespaces.name" => nil,
        "gh.request_id" => "1234",
      ))

      Codespaces::AsyncOperation.create(operation: :create_codespace)
      assert_dogstats_increment(1, "codespaces.async_operations.requested", tags: ["operation:create_codespace", "state:requested", "codespace_unavailable:true"])
    end

    test "starting an operation results in logs and metrics" do
      codespace = create(:codespace)
      op = create(:codespaces_async_operation, codespace: codespace)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "started",
        "gh.codespaces.async_operation.request_to_start_seconds" => 600.0,
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.created_at + 10.minutes) do
        op.mark_as_started
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_start_seconds", tags: ["operation:update_storage", "state:started"])
    end

    test "starting a started operation results in nothing happening" do
      codespace = create(:codespace)
      op = create(:codespaces_async_operation, codespace: codespace)
      op.touch(:op_started_at)

      GitHub.logger.expects(:info).never

      assert_no_changes -> { op.reload.op_started_at } do
        Timecop.freeze(op.created_at + 10.minutes) do
          op.mark_as_started
        end
      end

      assert_dogstats_distribution(0, "codespaces.async_operations.request_to_start_seconds", tags: ["operation:update_storage", "state:started"])
    end

    test "starting an ended operation results in nothing happening" do
      codespace = create(:codespace)
      op = create(:codespaces_async_operation, codespace: codespace)
      op.touch(:op_ended_at)

      GitHub.logger.expects(:info).never

      assert_no_changes -> { op.reload.op_started_at } do
        assert_no_changes -> { op.reload.op_ended_at } do
          Timecop.freeze(op.created_at + 10.minutes) do
            op.mark_as_started
          end
        end
      end

      assert_dogstats_distribution(0, "codespaces.async_operations.request_to_start_seconds", tags: ["operation:update_storage", "state:started"])
    end

    test "ending an operation results in logs and metrics" do
      codespace = create(:codespace)
      op = create(:codespaces_async_operation, :started, codespace: codespace)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "ended",
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
        op.mark_as_ended # Should only end it once even if called twice
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["operation:update_storage", "state:ended"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["operation:update_storage", "state:ended"])
    end

    test "ending an operation without a codespace but with a user results in automated testing tagged metrics and logs" do
      user = create(:user)
      GitHub.flipper[:codespaces_automated_testing].enable(user)
      op = create(:codespaces_async_operation, :started, codespace: nil, user: user, operation: :create_codespace)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "create_codespace",
        "gh.codespaces.automated_testing" => true,
        "gh.codespaces.async_operation.state" => "ended",
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => nil,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["operation:create_codespace", "state:ended", "codespaces_automated_testing:true"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["operation:create_codespace", "state:ended", "codespaces_automated_testing:true"])
    end

    test "ending an operation without a codespace but with a user and non-production vscs_target results in automated testing tagged metrics and logs" do
      user = create(:user)
      op = create(:codespaces_async_operation, :started, codespace: nil, user: user, operation: :create_codespace, vscs_target: :local)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "create_codespace",
        "gh.codespaces.automated_testing" => true,
        "gh.codespaces.async_operation.state" => "ended",
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => nil,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["operation:create_codespace", "state:ended", "codespaces_automated_testing:true"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["operation:create_codespace", "state:ended", "codespaces_automated_testing:true"])
    end

    test "ending an unstarted operation results in logs and metrics" do
      codespace = create(:codespace)
      op = create(:codespaces_async_operation, codespace: codespace)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "ended",
        "gh.codespaces.async_operation.request_to_end_seconds" => 300.0,
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.created_at + 5.minutes) do
        op.mark_as_ended
      end

      refute_dogstats_distribution("codespaces.async_operations.start_to_end_seconds", tags: ["operation:update_storage", "state:ended"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["operation:update_storage", "state:ended"])
    end

    test "codespace tags are included when available" do
      codespace = create(:codespace)
      GitHub.flipper[:codespaces_automated_testing].enable(codespace.owner)
      op = create(:codespaces_async_operation, :started, codespace: codespace)
      op.update!(op_started_at: op.created_at + 5.minutes)

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["codespaces_automated_testing:true", "location:#{codespace.location}"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["codespaces_automated_testing:true", "location:#{codespace.location}"])
      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:ended", "codespaces_automated_testing:true"])
    end

    test "extra tags included for repo flagged into codespaces_tag_repo_in_async_operation" do
      repo = create(:repository)
      GitHub.flipper[:codespaces_tag_repo_in_async_operation].enable(repo)

      environment_data = { prebuild_type: "CodespacePool", create_from_prebuild: true, is_allocated_from_pool: true }
      codespace = create(:codespace, repository: repo, environment_data: environment_data)

      op = create(:codespaces_async_operation, :started, codespace: codespace)
      op.update!(op_started_at: op.created_at + 5.minutes)

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["repo_id:#{repo.id}"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["repo_id:#{repo.id}", "create_from_prebuild:#{codespace.environment_data&.create_from_prebuild}", "prebuild_type:#{codespace.environment_data&.prebuild_type}", "is_allocated_from_pool:#{codespace.environment_data&.is_allocated_from_pool}", "location:#{codespace.location}"])
      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:ended", "repo_id:#{repo.id}"])
    end

    test "automated testing tag is included if we provide a user to the operation" do
      user = create(:user)
      GitHub.flipper[:codespaces_automated_testing].enable(user)
      op = create(:codespaces_async_operation, codespace: nil, user:)

      assert_dogstats_increment("codespaces.async_operations.requested", tags: ["operation:update_storage", "codespaces_automated_testing:true"])
    end

    test "automated testing tag is included in logs if we provide a flagged user to the operation" do
      user = create(:user)
      GitHub.flipper[:codespaces_automated_testing].enable(user)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", has_entries(
        "gh.codespaces.automated_testing" => true,
      ))

      op = create(:codespaces_async_operation, codespace: nil, user:)
    end

    test "codespace tags are included when the codespace is set after initial creation" do
      codespace = create(:codespace)
      GitHub.flipper[:codespaces_automated_testing].enable(codespace.owner)
      op = create(:codespaces_async_operation, :started)
      op.update!(codespace: codespace, op_started_at: op.created_at + 5.minutes)

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_distribution(1, "codespaces.async_operations.start_to_end_seconds", tags: ["codespaces_automated_testing:true", "location:#{codespace.location}"])
      assert_dogstats_distribution(1, "codespaces.async_operations.request_to_end_seconds", tags: ["codespaces_automated_testing:true", "location:#{codespace.location}"])
      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:ended", "codespaces_automated_testing:true"])
    end

    test "state is succeeded when success is true" do
      codespace = create(:codespace)
      operation = :update_storage
      op = create(:codespaces_async_operation, :started, codespace: codespace, operation: operation)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "succeeded",
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_succeeded
      end

      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:succeeded"])
    end

    test "state is failed when success is false" do
      codespace = create(:codespace)
      operation = :update_storage
      op = create(:codespaces_async_operation, :started, codespace: codespace, operation: operation)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", equals(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "failed",
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => codespace.name,
        "gh.request_id" => "1234",
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_failed
      end

      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:failed"])
    end

    test "state is ended when success is nil" do
      codespace = create(:codespace)
      operation = :update_storage
      op = create(:codespaces_async_operation, :started, codespace: codespace, operation: operation)
      op.update!(op_started_at: op.created_at + 5.minutes)
      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_ended
      end

      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:ended"])
    end

    test "class methods tag appropriately" do
      Codespaces::AsyncOperation.report_failure(operation: :create_codespace, codespaces_automated_testing: false)
      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:create_codespace", "state:failed", "failsafe_reporting:true"])
      Codespaces::AsyncOperation.report_failure(operation: :create_codespace, codespaces_automated_testing: true)
      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:create_codespace", "state:failed", "failsafe_reporting:true", "codespaces_automated_testing:true"])
    end

    test "class methods can log additional details" do
      GitHub.flipper[:codespaces_failsafe_report_splunk].enable
      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", has_entries(
        "gh.codespaces.async_operation.name" => "create_codespace",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "failed",
        "gh.request_id" => "1234",
        "gh.codespaces.async_operation.failure_reason" => "Kaboom",
        "gh.codespaces.async_operation.caller" => anything,
      ))
      Codespaces::AsyncOperation.report_failure(operation: :create_codespace, failure_reason: "Kaboom")
    end

    test "failing an operation logs additional details" do
      codespace = create(:codespace)
      operation = :update_storage
      op = create(:codespaces_async_operation, :started, codespace: codespace, operation: operation)
      op.update!(op_started_at: op.created_at + 5.minutes)

      GitHub.logger.expects(:info).with(
        "codespaces async operation changed state", has_entries(
        "gh.codespaces.async_operation.id" => op.id,
        "gh.codespaces.async_operation.name" => "update_storage",
        "gh.codespaces.automated_testing" => false,
        "gh.codespaces.async_operation.state" => "failed",
        "gh.request_id" => "1234",
        "gh.codespaces.async_operation.failure_reason" => "Codespaces::Client::TimeoutError",
        "gh.codespaces.async_operation.caller" => anything,
        "gh.codespaces.async_operation.request_to_start_seconds" => 300.0,
        "gh.codespaces.async_operation.request_to_end_seconds" => 600.0,
        "gh.codespaces.async_operation.start_to_end_seconds" => 300.0,
        "gh.codespaces.name" => codespace.name,
      ))

      Timecop.freeze(op.op_started_at + 5.minutes) do
        op.mark_as_failed(failure_reason: Codespaces::Client::TimeoutError.new)
      end

      assert_dogstats_increment("codespaces.async_operations.ended", tags: ["operation:update_storage", "state:failed", "failure_reason:Codespaces::Client::TimeoutError"])
    end
  end

  context "hung_operations" do
    test "operations that are created but not yet started are not returned" do
      create(:codespaces_async_operation, operation: :start_codespace)

      assert_equal 0, Codespaces::AsyncOperation.hung_operations.count
    end

    test "operations that are not finished but were started more than $timeout ago are returned" do
      create(:codespaces_async_operation, op_started_at: 110.minutes.ago, operation: :start_codespace)

      assert_equal 1, Codespaces::AsyncOperation.hung_operations.count
    end

    test "operations that are not finished but were started more than $timeout ago but from the wrong operation type are not returned" do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago, operation: :update_storage)

      assert_equal 0, Codespaces::AsyncOperation.hung_operations.count
    end

    test "finished operations are not returned" do
      create(:codespaces_async_operation, op_started_at: 110.minutes.ago, op_ended_at: 2.minutes.ago, operation: :start_codespace)

      assert_equal 0, Codespaces::AsyncOperation.hung_operations.count
    end
  end

  context "ongoing_operations" do
    test "operations that are created but not yet started are not returned" do
      create(:codespaces_async_operation)

      assert_equal 0, Codespaces::AsyncOperation.ongoing_operations.count
    end

    test "operations that are not finished but were started more than $reverify_after ago are returned" do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago)

      assert_equal 1, Codespaces::AsyncOperation.ongoing_operations.count
    end

    test "finished operations are not returned" do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago, op_ended_at: 2.minutes.ago)

      assert_equal 0, Codespaces::AsyncOperation.ongoing_operations.count
    end
  end

  context "unstarted_operations" do
    test "operations that are created but not yet started are returned after some timeout" do
      create(:codespaces_async_operation, created_at: 6.minutes.ago)

      assert_equal 1, Codespaces::AsyncOperation.unstarted_operations.count
    end

    test "operations that have started are not included" do
      create(:codespaces_async_operation, op_started_at: 1.minute.ago)

      assert_equal 0, Codespaces::AsyncOperation.unstarted_operations.count
    end

    test "operations that have finished are not included" do
      create(:codespaces_async_operation, op_ended_at: 1.minute.ago)

      assert_equal 0, Codespaces::AsyncOperation.unstarted_operations.count
    end

    test "operations that haven't started yet, but aren't timed out yet aren't included" do
      create(:codespaces_async_operation, created_at: 1.minute.ago)

      assert_equal 0, Codespaces::AsyncOperation.unstarted_operations.count
    end
  end

  context "ensure_no_blocking_pending!" do
    test "finds pending operation when there is an incomplete async operation" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, codespace: codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
      end
    end

    test "doesn't find pending operation once it has been completed" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, :finished, codespace: codespace)

      assert_nil Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
    end

    test "doesn't find pending operation if there haven't been any" do
      codespace = create(:codespace)

      assert_nil Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
    end

    test "finds a pending operation if there have been both completed and incomplete async operations" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, codespace: codespace)
      create(:codespaces_async_operation, :finished, codespace: codespace)

      assert_raises Codespaces::AsyncOperation::PendingError do
        Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
      end
    end

    test "finds blocking pending operations" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, codespace: codespace, operation: :update_storage)

      assert_raises Codespaces::AsyncOperation::PendingError do
        Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
      end
    end

    test "doesn't find non-blocking pending operations" do
      codespace = create(:codespace)
      create(:codespaces_async_operation, codespace: codespace, operation: :start_codespace)

      assert_nil Codespaces::AsyncOperation.ensure_no_blocking_pending!(codespace)
    end
  end

  context "start_timed_out?" do
    test "returns false if operation hasn't started" do
      async_operation = Codespaces::AsyncOperation.new(codespace: @codespace, operation: :update_storage)

      refute async_operation.start_timed_out?
    end

    test "returns false if operation hasn't taken longer than the defined start_timeout" do
      async_operation = Codespaces::AsyncOperation.create(codespace: @codespace, operation: :update_storage)
      refute async_operation.start_timed_out?
    end

    test "returns true if operation has taken longer than the operation's defined start_timeout" do
      update_storage_operation_timeout =
        Codespaces::AsyncOperation::OPERATION_CONFIG[:update_storage].start_timeout

      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :update_storage,
        created_at: (update_storage_operation_timeout + 10.minutes).ago
      )
      assert async_operation.start_timed_out?
    end

    test "returns false if the operation was started but we're asking after the start timeout since it was created" do
      update_storage_operation_timeout =
        Codespaces::AsyncOperation::OPERATION_CONFIG[:update_storage].start_timeout

      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :update_storage,
        created_at: (update_storage_operation_timeout + 10.minutes).ago,
        op_started_at: (update_storage_operation_timeout + 9.minutes).ago
      )
      refute async_operation.start_timed_out?
    end
  end

  context "finish_timed_out?" do
    test "returns false if the operation has no finish_timeout" do
      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :update_storage,
        created_at: 1.day.ago,
        op_started_at: 1.day.ago,
      )
      refute async_operation.finish_timed_out?
    end

    test "returns false if operation hasn't started" do
      async_operation = Codespaces::AsyncOperation.new(codespace: @codespace, operation: :start_codespace, created_at: 1.day.ago)

      refute async_operation.finish_timed_out?
    end

    test "returns false if operation hasn't taken longer than the defined finish_timeout" do
      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :start_codespace,
        created_at: 1.day.ago,
        op_started_at: Time.now,
      )
      refute async_operation.finish_timed_out?
    end

    test "returns true if operation has taken longer than the operation's defined finish_timeout" do
      finish_timeout =
        Codespaces::AsyncOperation::OPERATION_CONFIG[:start_codespace].finish_timeout

      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :start_codespace,
        created_at: (finish_timeout + 10.minutes).ago,
        op_started_at: (finish_timeout + 9.minutes).ago
      )
      assert async_operation.finish_timed_out?
    end

    test "returns false if the operation was finished but we're asking after the finish timeout since it was created" do
      finish_timeout =
        Codespaces::AsyncOperation::OPERATION_CONFIG[:start_codespace].finish_timeout

      async_operation = Codespaces::AsyncOperation.create(
        codespace: @codespace,
        operation: :start_codespace,
        created_at: (finish_timeout + 10.minutes).ago,
        op_started_at: (finish_timeout + 9.minutes).ago,
        op_ended_at: (finish_timeout + 8.minutes).ago
      )
      refute async_operation.finish_timed_out?
    end
  end
end
