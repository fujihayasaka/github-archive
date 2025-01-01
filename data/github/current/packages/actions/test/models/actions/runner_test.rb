# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"
require "test_helpers/launch/self_hosted_runners_helper"

class Actions::RunnerTest < GitHub::TestCase
  include Launch::SelfHostedRunnersHelper

  fixtures do
    @member = create :user
    @org = create :organization, admins: [@member]
    @repository = create :repository, owner: @org
    @enterprise = create :business, owners: [@member], organizations: [@org]
  end

  setup do
    @system_labels = [
      GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 1, name: "self-hosted", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 2, name: "linux", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 3, name: "x64", type: "system")
    ]

    @user_labels = [
      GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 4, name: "gpu", type: "user"),
      # This is a user label whose value is intentionally duplicative of one that could be a system label
      GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 5, name: "windows", type: "user")
    ]

    @runners = [
      GitHub::Launch::Services::Selfhostedrunners::Runner.new(id: 1, name: "A runner", os: "linux", arch: "x64", status: "online", current_parallelism: 1, labels: @system_labels + @user_labels),
      GitHub::Launch::Services::Selfhostedrunners::Runner.new(id: 1, name: "A runner", os: "linux", arch: "x64", status: "online", labels: @system_labels),
      GitHub::Launch::Services::Selfhostedrunners::Runner.new(id: 2, name: "Another runner", os: "linux", arch: "arm32", status: "offline", labels: @system_labels)
    ]

    @get_runner_response = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: @runners.first)

    @macos_label = GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 6, name: "macos", type: "system")
    @windows_label = GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 7, name: "windows", type: "system")
    @x32_label = GitHub::Launch::Services::Selfhostedrunners::Label.new(id: 8, name: "x32", type: "system")
    unassigned_system_labels = [@macos_label, @windows_label, @x32_label]

    typeless_defined_labels = (@system_labels + unassigned_system_labels + @user_labels)
      .map { |label| GitHub::Launch::Services::Selfhostedrunners::Label.new(id: label.id, name: label.name, type: "") }
    @list_labels_response = GitHub::Launch::Services::Selfhostedrunners::ListLabelsResponse.new(labels: typeless_defined_labels)
  end

  context ".get!" do
    test "raises when an error is raised" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 503, response: nil)

      assert_raises { Actions::Runner.get!(@repository, @runners.first.id) }
    end

    test "returns nil for non-existent runner" do
      mock_get_runner(owner: @repository, runner_id: @runners.last.id + 1, status: 200, response: nil)

      runner = Actions::Runner.get!(@repository, @runners.last.id + 1)
      assert_nil runner
    end

    test "returns expected model instance for existent runner" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get!(@repository, first_runner.id)

      refute_nil runner
      assert_equal first_runner.id, runner.id
      assert_equal first_runner.name, runner.name
      assert_equal first_runner.os, runner.os
      assert_equal first_runner.arch, runner.arch
      refute_empty runner.status
      assert_equal first_runner.current_parallelism, runner.current_parallelism
      assert_equal first_runner.labels, runner.labels
      refute_nil runner.owner
    end

    test "returns expected model instance with repository as owner" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get!(@repository, first_runner.id)

      refute_nil runner
      assert_equal @repository, runner.owner
    end

    test "returns expected model instance with organization as owner" do
      mock_get_runner(owner: @org, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get!(@org, first_runner.id)

      refute_nil runner
      assert_equal @org, runner.owner
    end

    test "returns expected model instance with enterprise as owner" do
      mock_get_runner(owner: @enterprise, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get!(@enterprise, first_runner.id)

      refute_nil runner
      assert_equal @enterprise, runner.owner
    end
  end

  context ".get" do
    test "returns nil when an error is raised" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 503, response: nil)

      runner = Actions::Runner.get(@repository, @runners.first.id)
      assert_nil runner
    end

    test "returns nil for non-existent runner" do
      mock_get_runner(owner: @repository, runner_id: @runners.last.id + 1, status: 404, response: nil)

      runner = Actions::Runner.get(@repository, @runners.last.id + 1)
      assert_nil runner
    end

    test "returns expected model instance for existent runner" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get(@repository, first_runner.id)

      refute_nil runner
      assert_equal first_runner.id, runner.id
      assert_equal first_runner.name, runner.name
      assert_equal first_runner.os, runner.os
      assert_equal first_runner.arch, runner.arch
      refute_empty runner.status
      assert_equal first_runner.current_parallelism, runner.current_parallelism
      assert_equal first_runner.labels, runner.labels
      refute_nil runner.owner
    end

    test "returns expected model instance with repository as owner" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get(@repository, first_runner.id)

      refute_nil runner
      assert_equal @repository, runner.owner
    end

    test "returns expected model instance with organization as owner" do
      mock_get_runner(owner: @org, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get(@org, first_runner.id)

      refute_nil runner
      assert_equal @org, runner.owner
    end

    test "returns expected model instance with enterprise as owner" do
      mock_get_runner(owner: @enterprise, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      first_runner = @runners.first
      runner = Actions::Runner.get(@enterprise, first_runner.id)

      refute_nil runner
      assert_equal @enterprise, runner.owner
    end

  end

  context "#status" do
    test "returns 'active' for online instance with current_parallelism greater than 0" do
      target_runner = @runners.first
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: target_runner.id, status: 200, response: resp)
      runner = Actions::Runner.get(@repository, target_runner.id)

      assert_equal "online", target_runner.status
      assert_operator 0, :<, target_runner.current_parallelism
      assert_equal "active", runner.status
    end

    test "returns 'idle' for online instance with current_parallelism of 0" do
      target_runner = @runners[1]
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: target_runner.id, status: 200, response: resp)

      runner = Actions::Runner.get(@repository, target_runner.id)

      assert_equal "online", target_runner.status
      assert_equal 0, target_runner.current_parallelism
      assert_equal "idle", runner.status
    end

    test "returns 'offline' for offline instance" do
      target_runner = @runners.last
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: target_runner.id, status: 200, response: resp)

      runner = Actions::Runner.get(@repository, target_runner.id)

      assert_equal "offline", target_runner.status
      assert_equal "offline", runner.status
    end

    test "returns 'disabled' for repo-level runners when policy does not allow them" do
      target_runner = @runners.first
      mock_get_runner(owner: @repository, runner_id: target_runner.id, status: 200, response: @get_runner_response)

      runner = Actions::Runner.get(@repository, target_runner.id)
      @org.disable_repo_self_hosted_runners(actor: @member)
      Repository.any_instance.stubs(:repo_self_hosted_runners_enabled?).returns(false)

      assert_equal "disabled", runner.status

      mock_get_runner(owner: @org, runner_id: target_runner.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@org, target_runner.id)
      assert_equal "active", runner.status

      mock_get_runner(owner: @enterprise, runner_id: target_runner.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@enterprise, target_runner.id)
      assert_equal "active", runner.status
    end
  end

  context "#system_labels" do
    test "returns only system labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)

      assert_equal @system_labels, runner.system_labels
    end
  end

  context "#custom_labels" do
    test "returns only custom labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)

      assert_equal @user_labels, runner.custom_labels
    end
  end

  context "#add_custom_labels!" do
    test "raises if owning entity is unknown" do
      runner = Actions::Runner.from_rpc_object(@get_runner_response.runner, owner: nil)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.add_custom_labels!(runner.custom_labels.map(&:name))
      end
      assert_equal "Cannot identify runner's owning entity", error.message
      assert_equal 500, error.status
    end

    test "returns true if no labels provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      succeeded = runner.add_custom_labels!(nil)
      assert succeeded
      assert_same original_labels, runner.labels
    end

    test "returns true if empty labels provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      succeeded = runner.add_custom_labels!([])
      assert succeeded
      assert_same original_labels, runner.labels
    end

    test "returns true if provided labels already present" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      succeeded = runner.add_custom_labels!(runner.custom_labels.map(&:name))
      assert succeeded
      assert_same original_labels, runner.labels
    end

    test "raises when attempting to add duplicate system labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      some_system_label_names = [@system_labels.last.name, @system_labels.first.name]
      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.add_custom_labels!(some_system_label_names + ["accelerated"])
      end
      assert_equal 422, error.status
      assert_equal "Cannot add labels that duplicate existing read-only labels: #{some_system_label_names.join(', ')}", error.message
      assert_same original_labels, runner.labels
    end

    test "returns true when adding defined labels not present on the runner" do
      target_runner = @runners.last

      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.last.id, status: 200, response: resp)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      updated_runner = target_runner.dup
      updated_runner.labels = target_runner.labels + @user_labels
      mock_update_labels(owner: @repository, additions: [@windows_label.id] + @user_labels.map(&:id), updated_runner:)

      requested_label_names = @user_labels.map(&:name)
      succeeded = runner.add_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true when adding undefined labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)
      new_labels = [
        mock_create_label(owner: @repository, name: "accelerated"),
        mock_create_label(owner: @repository, name: "optimized"),
      ]

      first_runner = @runners.first
      updated_runner = first_runner.dup
      updated_runner.labels = first_runner.labels + new_labels
      mock_update_labels(owner: @repository, additions: new_labels.map(&:id), updated_runner:)

      runner = Actions::Runner.get(@repository, first_runner.id)
      original_labels = runner.labels

      requested_label_names = new_labels.map(&:name)
      succeeded = runner.add_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true when adding unapplied system labels as user labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)
      new_labels = [
        GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "x32", type: "user")
      ]

      first_runner = @runners.first
      updated_runner = first_runner.dup
      updated_runner.labels = first_runner.labels + new_labels
      mock_update_labels(owner: @repository, additions: [@x32_label.id], updated_runner:)

      runner = Actions::Runner.get(@repository, first_runner.id)
      original_labels = runner.labels

      requested_label_names = new_labels.map(&:name)
      succeeded = runner.add_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true when adding a mixture of defined and undefined labels" do
      new_labels = [
        mock_create_label(owner: @repository, name: "accelerated"),
        mock_create_label(owner: @repository, name: "optimized"),
      ]

      last_runner = @runners.last
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: last_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.last.id, status: 200, response: resp)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      updated_runner = last_runner.dup
      updated_runner.labels = last_runner.labels + @user_labels + new_labels
      mock_update_labels(owner: @repository, additions: [@windows_label.id] + @user_labels.map(&:id) + new_labels.map(&:id), updated_runner:)

      runner = Actions::Runner.get(@repository, last_runner.id)
      original_labels = runner.labels

      requested_label_names = @user_labels.map(&:name) + new_labels.map(&:name)
      succeeded = runner.add_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end
  end

  context "#replace_all_custom_labels!" do
    test "raises if owning entity is unknown" do
      runner = Actions::Runner.from_rpc_object(@get_runner_response.runner, owner: nil)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.replace_all_custom_labels!(runner.custom_labels.map(&:name))
      end
      assert_equal "Cannot identify runner's owning entity", error.message
      assert_equal 500, error.status
    end

    test "returns true and removes all custom labels if no labels provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      target_runner = @runners.first
      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      runner = Actions::Runner.get(@repository, target_runner.id)

      refute_empty runner.system_labels
      refute_empty runner.custom_labels

      updated_runner = target_runner.dup
      updated_runner.labels = system_labels
      mock_update_labels(owner: @repository, removals: runner.custom_labels.map(&:id), updated_runner:)

      succeeded = runner.replace_all_custom_labels!(nil)
      assert succeeded
      refute_empty runner.system_labels
      assert_empty runner.custom_labels
    end

    test "returns true and removes all custom labels if empty labels provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      target_runner = @runners.first
      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      runner = Actions::Runner.get(@repository, target_runner.id)

      refute_empty runner.system_labels
      refute_empty runner.custom_labels

      updated_runner = target_runner.dup
      updated_runner.labels = system_labels
      mock_update_labels(owner: @repository, removals: runner.custom_labels.map(&:id), updated_runner:)

      succeeded = runner.replace_all_custom_labels!([])
      assert succeeded
      refute_empty runner.system_labels
      assert_empty runner.custom_labels
    end

    test "returns true if provided labels are an exact match" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      succeeded = runner.replace_all_custom_labels!(runner.custom_labels.map(&:name))
      assert succeeded
      assert_same original_labels, runner.labels
    end

    test "raises when attempting to set duplicate system labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)
      original_labels = runner.labels

      some_system_label_names = [@system_labels.last.name, @system_labels.first.name]
      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.replace_all_custom_labels!(some_system_label_names + ["accelerated"])
      end
      assert_equal 422, error.status
      assert_equal "Cannot set labels that duplicate existing read-only labels: #{some_system_label_names.join(', ')}", error.message
      assert_same original_labels, runner.labels
    end

    test "returns true and updates as expected when setting defined labels not present on the runner" do
      target_runner = @runners.last
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.last.id, status: 200, response: resp)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      updated_runner = target_runner.dup
      updated_runner.labels = target_runner.labels + @user_labels
      mock_update_labels(owner: @repository, additions: [@windows_label.id] + @user_labels.map(&:id), updated_runner:)

      requested_label_names = @user_labels.map(&:name)
      succeeded = runner.replace_all_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true and updates as expected when setting undefined labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      new_labels = [
        mock_create_label(owner: @repository, name: "accelerated"),
        mock_create_label(owner: @repository, name: "optimized"),
      ]

      first_runner = @runners.first
      updated_runner = first_runner.dup
      updated_runner.labels = system_labels + new_labels
      mock_update_labels(
        owner: @repository,
        additions: new_labels.map(&:id),
        removals: @user_labels.map(&:id),
        updated_runner:,
      )

      runner = Actions::Runner.get(@repository, first_runner.id)
      original_labels = runner.labels

      requested_label_names = new_labels.map(&:name)
      succeeded = runner.replace_all_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      refute_includes runner.labels.map(&:name), @user_labels.first.name
      refute_includes runner.labels.map(&:name), @user_labels.last.name
      assert_equal @system_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true and update as as expected when setting unapplied system labels as user labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      new_labels = [
        GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "x32", type: "user")
      ]

      first_runner = @runners.first
      updated_runner = first_runner.dup
      updated_runner.labels = first_runner.labels + new_labels
      mock_update_labels(
        owner: @repository,
        additions: [@x32_label.id],
        removals: @user_labels.map(&:id),
        updated_runner:,
      )

      runner = Actions::Runner.get(@repository, first_runner.id)
      original_labels = runner.labels

      requested_label_names = new_labels.map(&:name)
      succeeded = runner.replace_all_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end

    test "returns true when setting a mixture of defined and undefined labels" do
      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      new_labels = [
        mock_create_label(owner: @repository, name: "accelerated"),
        mock_create_label(owner: @repository, name: "optimized"),
      ]

      first_runner = @runners.first
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: first_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      mock_list_labels(owner: @repository, status: 200, response: @list_labels_response)

      updated_runner = first_runner.dup
      updated_runner.labels = system_labels + @user_labels[0..0] + new_labels
      mock_update_labels(
        owner: @repository,
        additions: new_labels.map(&:id),
        removals: [@user_labels.second.id],
        updated_runner:,
      )

      runner = Actions::Runner.get(@repository, first_runner.id)
      original_labels = runner.labels

      requested_label_names = @user_labels[0..0].map(&:name) + new_labels.map(&:name)
      succeeded = runner.replace_all_custom_labels!(requested_label_names)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_includes original_labels.map(&:name), @user_labels.last.name
      refute_includes runner.labels.map(&:name), @user_labels.last.name
      assert_equal @system_labels.map(&:name) + requested_label_names, runner.labels.map(&:name)
    end
  end

  context "#remove_all_custom_labels!" do
    test "raises if owning entity is unknown" do
      runner = Actions::Runner.from_rpc_object(@get_runner_response.runner, owner: nil)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_all_custom_labels!
      end
      assert_equal "Cannot identify runner's owning entity", error.message
      assert_equal 500, error.status
    end

    test "returns true if no custom labels are present" do
      target_runner = @runners.last
      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.last.id, status: 200, response: resp)

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      refute_empty runner.system_labels
      assert_empty runner.custom_labels

      succeeded = runner.remove_all_custom_labels!
      assert succeeded
      assert_same original_labels, runner.labels
      refute_empty runner.system_labels
      assert_empty runner.custom_labels
    end

    test "returns true and removes all custom labels" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)

      target_runner = @runners.first
      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      refute_empty runner.system_labels
      refute_empty runner.custom_labels

      updated_runner = target_runner.dup
      updated_runner.labels = system_labels
      mock_update_labels(owner: @repository, removals: runner.custom_labels.map(&:id), updated_runner:)

      succeeded = runner.remove_all_custom_labels!
      assert succeeded
      refute_same original_labels, runner.labels
      refute_empty runner.system_labels
      assert_empty runner.custom_labels
    end
  end

  context "#remove_custom_label!" do
    test "raises if owning entity is unknown" do
      runner = Actions::Runner.from_rpc_object(@get_runner_response.runner, owner: nil)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!(runner.labels.last.name)
      end
      assert_equal "Cannot identify runner's owning entity", error.message
      assert_equal 500, error.status
    end

    test "raises if no label provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!(nil)
      end
      assert_equal "Label name not provided", error.message
      assert_equal 422, error.status
    end

    test "raises if blank label provided" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!(" ")
      end
      assert_equal "Label name not provided", error.message
      assert_equal 422, error.status
    end

    test "raises if provided label is not present on the runner" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)
      runner = Actions::Runner.get(@repository, @runners.first.id)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!("accelerated")
      end
      assert_equal "Runner does not have that label", error.message
      assert_equal 404, error.status
    end

    test "raises if provided label somehow matches multiple on the runner" do
      # This state should not actually be possible, but we're testing for it
      target_runner = @runners.first.dup
      duplicate_system_as_user_labels = [GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "x64", type: "user")]
      target_runner.labels = target_runner.labels + duplicate_system_as_user_labels

      resp = GitHub::Launch::Services::Selfhostedrunners::GetRunnerResponse.new(runner: target_runner)
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: resp)

      runner = Actions::Runner.get(@repository, target_runner.id)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!(duplicate_system_as_user_labels.first.name)
      end
      assert_equal "Found more than one matching label", error.message
      assert_equal 500, error.status
    end

    test "raises if provided with a system label" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)

      runner = Actions::Runner.get(@repository, @runners.first.id)

      error = assert_raises Actions::Runner::RunnerServiceError do
        runner.remove_custom_label!(@system_labels.last.name)
      end
      assert_equal "Cannot remove read-only label", error.message
      assert_equal 422, error.status
    end

    test "returns true and updates as expected when removing last existing user label" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)

      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      target_runner = @runners.first
      updated_runner = target_runner.dup
      updated_runner.labels = system_labels + @user_labels[0...-1]
      mock_update_labels(owner: @repository, removals: [@user_labels.last.id], updated_runner:)

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      succeeded = runner.remove_custom_label!(original_labels.last.name)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal original_labels[0...-1].map(&:name), runner.labels.map(&:name)
    end

    test "returns true and updates as expected when removing not-last existing user label" do
      mock_get_runner(owner: @repository, runner_id: @runners.first.id, status: 200, response: @get_runner_response)

      # Poor workaround to get the system labels in the expected wrapper
      system_labels = @runners.last.labels

      target_runner = @runners.first
      updated_runner = target_runner.dup
      updated_runner.labels = system_labels + @user_labels[1..-1]
      mock_update_labels(owner: @repository, removals: [@user_labels.first.id], updated_runner:)

      runner = Actions::Runner.get(@repository, target_runner.id)
      original_labels = runner.labels

      succeeded = runner.remove_custom_label!(original_labels[-2].name)
      assert succeeded
      refute_same original_labels, runner.labels
      assert_equal (original_labels[0...-2] + original_labels[-1..-1]).map(&:name), runner.labels.map(&:name)
    end
  end

end
