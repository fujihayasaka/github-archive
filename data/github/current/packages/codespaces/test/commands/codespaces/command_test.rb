# typed: true
# frozen_string_literal: true

require "test_helper"

class Codespaces::CommandTest < GitHub::TestCase
  include DogstatsTestHelpers
  include GitHub::LoggerHelper

  class FakeCommand < Codespaces::Command
    attr_accessor :codespace

    def initialize(user = nil)
      @user = user
    end

    def perform; end
  end

  class FakeCommandWithoutPerformMethod < Codespaces::Command
    attr_accessor :codespace

    def initialize(user = nil)
      @user = user
    end

    def perform; end
  end

  class FakeCommandWithVscsTarget < Codespaces::Command
    def initialize(user = nil, vscs_target = nil)
      @user = user
      @vscs_target = vscs_target
    end

    def perform; end
  end

  class FakeCommandWithVscsTargetAndCodespace < FakeCommandWithVscsTarget
    attr_accessor :codespace

    def perform; end
  end

  class FakeCommandWithDBLookup < Codespaces::Command
    depends_on_clusters ApplicationRecord::Collab

    def initialize(user = nil)
      @user = user
    end

    def perform
      PullRequest.last
    end
  end

  test "Command.call invokes the #call method" do
    FakeCommand.any_instance.expects(:call)
    FakeCommand.call
  end

  test "#call invokes #perform" do
    command = FakeCommand.new
    command.expects(:perform).returns("hi")
    assert_equal "hi", command.call
  end

  test "callbacks are performed" do
    command = FakeCommand.new
    command.expects(:run_callbacks).with(:perform).once.yields

    command.call
  end

  test "reporting timing stats" do
    command = FakeCommand.new
    command.stubs(:perform)
    command.call
    assert_dogstats_distribution 1, "codespaces/command_test/fake_command.latency"
  end

  test "sets datadog tags for real owners" do
    command = FakeCommand.new
    codespace = create(:codespace, vscs_target: "production")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].disable(codespace.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "sets datadog tags for automated test owners" do
    command = FakeCommand.new
    codespace = create(:codespace, vscs_target: "production")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].enable(codespace.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "sets datadog tags based on vscs_target (production)" do
    command = FakeCommand.new
    codespace = create(:codespace, vscs_target: "production")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].disable(codespace.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal timing.tags, expected_tags
  end

  test "sets datadog tags based on vscs_target (non-production)" do
    # Non-production target.
    command = FakeCommand.new
    codespace = create(:codespace, vscs_target: "ppe")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].disable(codespace.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal timing.tags, expected_tags
  end

  # At the moment, there are couple of commands that deal with @user but are
  # not associated with a specific `codespace`, so our `#tags` implementation
  # doesn't send anything to Datadog for those. This test and the next one show
  # that we'll be ready for commands which have a `@user` + a `codespace` in the
  # future.
  test "sets datadog tags when there is a real @user" do
    user = create(:user)
    command = FakeCommand.new(user)
    codespace = create(:codespace, vscs_target: "production")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].disable(codespace.owner)
    GitHub.flipper[:codespaces_automated_testing].disable(user)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "sets datadog tags when there is an automated test @user" do
    user = create(:user)
    command = FakeCommand.new(user)
    codespace = create(:codespace, vscs_target: "production")
    command.codespace = codespace
    GitHub.flipper[:codespaces_automated_testing].disable(codespace.owner)
    GitHub.flipper[:codespaces_automated_testing].enable(user)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "vscs_target:#{codespace.vscs_target}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal timing.tags, expected_tags
  end

  test "sets datadog tags when there is a vscs_target instance method and codespace is nil" do
    user = create(:user)
    command = FakeCommandWithVscsTargetAndCodespace.new(user, "ppe")
    command.codespace = nil
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command_with_vscs_target_and_codespace.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "vscs_target:ppe",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "sets datadog tags when there is a vscs_target instance variable and codespace is present" do
    user = create(:user)
    command = FakeCommandWithVscsTargetAndCodespace.new(user, nil)
    codespace = create(:codespace, vscs_target: "ppe")
    command.codespace = codespace
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command_with_vscs_target_and_codespace.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "vscs_target:#{codespace.vscs_target}",
      "location:#{codespace.location}",
      "sku_name:#{codespace.sku_name}",
      "billable_owner_type:user",
      "is_copilot_workspace:false",
      "is_workspace_editor_cloud_environment:false",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "sets copilot workspace tag when codespace is a copilot workspace" do
    command = FakeCommand.new
    copilot_workspace = create(:copilot_workspace)
    command.codespace = copilot_workspace
    GitHub.flipper[:codespaces_automated_testing].disable(copilot_workspace.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    assert_includes timing.tags, "is_copilot_workspace:true"
  end

  test "sets workspace editor cloud environment tag when codespace is a workspace editor cloud environment" do
    command = FakeCommand.new
    workspace_editor_cloud_environment = create(:workspace_editor_cloud_environment)
    command.codespace = workspace_editor_cloud_environment
    GitHub.flipper[:codespaces_automated_testing].disable(workspace_editor_cloud_environment.owner)
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command.latency")[0]
    assert_includes timing.tags, "is_workspace_editor_cloud_environment:true"
  end

  test "sets datadog tags when there is a vscs_target instance variable and no codespace accessor" do
    user = create(:user)
    command = FakeCommandWithVscsTarget.new(user, "ppe")
    command.stubs(:perform)
    command.call
    timing = GitHub.dogstats.distributions("codespaces/command_test/fake_command_with_vscs_target.latency")[0]
    expected_tags = Set.new([
      "codespaces_automated_testing:true",
      "vscs_target:ppe",
    ])
    assert_equal expected_tags, timing.tags
  end

  test "includes error class in datadog tags" do
    command = FakeCommand.new
    command.stubs(:perform).raises(ArgumentError.new("Oh no!"))
    assert_raises ArgumentError do
      command.call
    end
    assert_dogstats_distribution "codespaces/command_test/fake_command.perform.errors.dist", tags: ["error:ArgumentError"]
  end

  test "includes error class and status in datadog tags when raising BadResponseError" do
    command = FakeCommand.new
    command.stubs(:perform).raises(Codespaces::Client::BadResponseError.new("Oh no!", 422))
    assert_raises Codespaces::Client::BadResponseError do
      command.call
    end
    assert_dogstats_distribution "codespaces/command_test/fake_command.perform.errors.dist", tags: ["error:Codespaces::Client::BadResponseError", "status:422"]
  end

  context "exception logging" do
    test "logs exceptions" do
      command = FakeCommand.new
      codespace = create(:codespace, vscs_target: "production")
      command.codespace = codespace
      command.stubs(:perform).raises(ArgumentError.new("Oh no!"))
      # We expect all the normal tags we set up in our commands plus the exception specific details from calling
      # log_exception.
      expected_log = command.send(:stats_tagger).all_semconv_tags.merge(
        "gh.codespaces.command" => "codespaces/command_test/fake_command",
        "exception.type" => "ArgumentError",
        "exception.message" => "Oh no!",
      )
      assert_logged **expected_log do
        # Exception should still get raised.
        assert_raises ArgumentError do
          command.call
        end
      end
    end
  end

  context "depends_on_clusters" do
    test "raises exception" do
      command = FakeCommandWithDBLookup.new
      assert_raises GitHub::DatabaseQueryDisabler::DatabaseDisabledError do
        command.call
      end
    end

    test "does not raise exception if not dev or test env" do
      Rails.env.stubs(:test?).returns(false)
      command = FakeCommandWithDBLookup.new
      command.call
    end
  end
end
