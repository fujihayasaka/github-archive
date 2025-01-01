# typed: true
# frozen_string_literal: true

require "github-launch"
require "test_helper"
require "test_helpers/launch/larger_runners_helper"

class Actions::LargerRunnerTest < GitHub::TestCase
  include Launch::LargerRunnersHelper

  fixtures do
    @member = create :user
    @org = create :organization, admins: [@member]
    @repository = create :repository, owner: @org
    @enterprise = create :business, owners: [@member], organizations: [@org]

    @org.onboard_larger_runners(actor: @member)
    @enterprise.onboard_larger_runners(actor: @member)
  end

  setup do
    @system_labels = [
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "self-hosted", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "linux", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "x64", type: "system")
    ]

    @user_labels = [
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "gpu", type: "user"),
      # This is a user label whose value is intentionally duplicative of one that could be a system label
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "windows", type: "user")
    ]

    @runners = [
      GitHub::Launch::Services::Largerrunners::Pool.new(id: 1, name: "PremiumRunner1", labels: ["gpu", "doesnt exist"], state: :Ready, platform: "linux-x64", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5),
      GitHub::Launch::Services::Largerrunners::Pool.new(id: 2, name: "PremiumRunner2", state: :Ready, platform: "Ubuntu", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5),
      GitHub::Launch::Services::Largerrunners::Pool.new(id: 3, name: "PremiumRunner3", state: :Ready, platform: "Ubuntu", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5)
    ]

    unassigned_system_labels = [
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "macos", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "windows", type: "system"),
      GitHub::Launch::Services::Selfhostedrunners::Label.new(name: "x32", type: "system")
    ]

    typeless_defined_labels = (@system_labels + unassigned_system_labels + @user_labels)
      .map { |label| GitHub::Launch::Services::Selfhostedrunners::Label.new(name: label.name, type: "") }
    list_labels_response = GitHub::Launch::Services::Selfhostedrunners::ListLabelsResponse.new(labels: typeless_defined_labels)
  end

  context ".get_larger_runner" do
    test "returns nil for non-existent runner" do
      GitHub::Launch::Services::Largerrunners::LargerRunnersClient.any_instance.expects(:get_pool)
        .returns(Twirp::ClientResp.new(data: nil, error: Twirp::Error.not_found("Not Found")))

      runner = Actions::LargerRunner.get_larger_runner(@org, pool_id: @runners.last.id + 1)
      assert_nil runner
    end

    test "returns expected model instance for existent runner" do
      mock_get_pool(@runners.first)

      first_runner = @runners.first
      runner = Actions::LargerRunner.get_larger_runner(@org, pool_id: first_runner.id)

      refute_nil runner
      runner = T.must(runner)
      assert_equal first_runner.id, runner.id
      assert_equal first_runner.name, runner.name
      assert_equal first_runner.state, runner.state
      assert_equal first_runner.runner_group_id, runner.runner_group_id
      assert_equal runner.labels.count, 3
      assert runner.labels.any? { |l| l.name == "gpu" }
      assert runner.labels.any? { |l| l.name == "doesnt exist" }
      assert runner.labels.any? { |l| l.name == runner.name }
    end

    test "returns runner with label from the pool" do
      mock_get_pool(@runners.first)

      first_runner = @runners.first
      runner = Actions::LargerRunner.get_larger_runner(@org, pool_id: first_runner.id)

      refute_nil runner
      runner = T.must(runner)
      assert_equal first_runner.id, runner.id
      assert runner.labels.any? { |l| l.name == "doesnt exist" }
    end
  end

  context "validations" do
    test "valid larger runner" do
      runner = build(
        :larger_runner,
        name: "test",
        platform: "linux-x64",
        runner_group_id: 1,
        runner_count: 2,
        labels: ["a"],
        maximum_runners: 1000,
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: nil
      )

      assert_valid runner
    end

    test "valid larger runner with linux-arm64 platform" do
      runner = build(
        :larger_runner,
        name: "linux-arm64 test",
        platform: "linux-arm64",
        runner_group_id: 1,
        runner_count: 2,
        labels: ["a"],
        maximum_runners: 1000,
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: nil
      )

      assert_valid runner
    end

    test "valid larger runner with win-arm64 platform" do
      runner = build(
        :larger_runner,
        name: "win-arm64 test",
        platform: "win-arm64",
        runner_group_id: 1,
        runner_count: 2,
        labels: ["a"],
        maximum_runners: 1000,
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: nil
      )

      assert_valid runner
    end

    test "valid larger runner with curated image on :create" do
      runner = build(
        :larger_runner,
        name: "test",
        platform: "linux-x64",
        runner_group_id: 1,
        runner_count: 2,
        labels: ["a"],
        maximum_runners: 1000,
        image: Actions::LargerRunner::ImageKey.new(source: :Curated, id: "Ubuntu20"),
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: nil
      )

      assert runner.valid?(:create)
    end

    test "valid larger runner with custom image on :create" do
      runner = build(
        :larger_runner,
        name: "test",
        platform: "linux-x64",
        runner_group_id: 1,
        runner_count: 2,
        labels: ["a"],
        maximum_runners: 1000,
        image: Actions::LargerRunner::ImageKey.new(source: :Custom),
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: "foo://example.com:123/"
      )

      assert runner.valid?(:create)
    end

    test "invalid larger runner with missing required parameters" do
      runner = build(
        :larger_runner,
        name: "",
        labels: %w[a b c]
      )

      refute_valid runner
      assert_equal runner.errors.full_messages, [
        "Name can't be blank",
        "Name is invalid",
        "Runner group can't be blank",
        "Runner group is not a number",
        "Machine spec can't be blank"]
    end

    test "invalid larger runner with missing required parameters on :create" do
      runner = build(
        :larger_runner,
        name: "",
        labels: %w[a b c]
      )

      refute runner.valid?(:create)
      assert_equal runner.errors.full_messages, [
        "Name can't be blank",
        "Name is invalid",
        "Runner group can't be blank",
        "Runner group is not a number",
        "Image is required",
        "Machine spec can't be blank"]
    end

    test "invalid larger runner with invalid required parameter" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        runner_group_id: 1,
        runner_count: 2,
        labels: [""],
        maximum_runners: 1000,
        image: Actions::LargerRunner::ImageKey.new(source: :Curated, id: nil),
        machine_spec_id: "example",
        is_public_ip_enabled: true,
        image_sas_uri: "foo://example.com:123/"
      )

      refute_valid runner
      assert_equal runner.errors.full_messages, [
        "Name can't be blank",
        "Name is invalid"]
    end
  end

  context "validate_image_key" do
    test "valid when curated image is provided" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Curated, id: "Ubuntu20")
      )

      runner.validate_image_key
      assert_empty runner.errors
    end

    test "valid when marketplace image is provided" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Marketplace, id: "NVIDIA")
      )

      runner.validate_image_key
      assert_empty runner.errors
    end

    test "valid when custom image is provided" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Custom),
        image_sas_uri: "foo://example.com:123/"
      )

      runner.validate_image_key
      assert_empty runner.errors
    end

    test "reports error when image is not provided" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image_sas_uri: "foo://example.com:123/"
      )

      runner.validate_image_key
      assert_equal runner.errors.full_messages, ["Image is required"]
    end

    test "reports error when image name is not provided for curated image" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Curated),
        image_sas_uri: "foo://example.com:123/"
      )

      runner.validate_image_key
      assert_equal runner.errors.full_messages, ["Image requires image name for curated and marketplace image sources"]
    end

    test "reports error when image name is not provided for marketplace image" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Marketplace),
        image_sas_uri: "foo://example.com:123/"
      )

      runner.validate_image_key
      assert_equal runner.errors.full_messages, ["Image requires image name for curated and marketplace image sources"]
    end

    test "reports error when sas url is not provided for custom image" do
      runner = build(
        :larger_runner,
        name: "",
        platform: "linux-x64",
        image: Actions::LargerRunner::ImageKey.new(source: :Custom),
      )

      runner.validate_image_key
      assert_equal runner.errors.full_messages, ["Image requires image_sas_uri for custom image source"]
    end
  end

  context ".larger_runners_for" do
    test "returns list of all runners" do
      list_pools_response = GitHub::Launch::Services::Largerrunners::ListPoolsResponse.new(pools: @runners)
      GitHub::Launch::Services::Largerrunners::LargerRunnersClient.any_instance
        .expects(:list_pools).returns(Twirp::ClientResp.new(data: list_pools_response))

      runners = Actions::LargerRunner.larger_runners_for(entity: @org)
      assert_equal runners.count, @runners.count
      actual = T.must(runners.first)
      assert_equal actual.labels.count, 3
      assert actual.labels.any? { |l| l.name == "gpu" }
      assert actual.labels.any? { |l| l.name == "doesnt exist" }
      assert actual.labels.any? { |l| l.name == actual.name }
    end

    test "returns list of runners with Public IP enabled" do
      public_ip = GitHub::Launch::Services::Largerrunners::PublicIP.new(enabled: true, prefix: "", length: 32)
      runner_with_public_ip = GitHub::Launch::Services::Largerrunners::Pool.new(id: 2, name: "PremiumRunnerWithPublicIP", state: :Ready, platform: "Ubuntu", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5, public_ip_enabled: true, public_ips: Array[public_ip])
      list_pools_response = GitHub::Launch::Services::Largerrunners::ListPoolsResponse.new(pools: [runner_with_public_ip])
      list_pools_request = GitHub::Launch::Services::Largerrunners::ListPoolsRequest.new(
        entity_id:  GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
        owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
        plan_owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
        entity_is_private: true,
        is_public_ip_enabled: { value: true }
      )

      GitHub::Launch::Services::Largerrunners::LargerRunnersClient.any_instance
        .expects(:list_pools).with(list_pools_request).returns(Twirp::ClientResp.new(data: list_pools_response))

      runners_with_public_ip = Actions::LargerRunner.larger_runners_for(entity: @org, is_public_ip_enabled: true)
      assert_equal runners_with_public_ip.count, 1
      actual = T.must(runners_with_public_ip.first)
      assert_equal actual.name, runner_with_public_ip.name
    end

    test "returns list of runners with Public IP disabled" do
      runner_without_public_ip = GitHub::Launch::Services::Largerrunners::Pool.new(id: 3, name: "PremiumRunnerWithoutPublicIP", state: :Ready, platform: "Ubuntu", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5)
      list_pools_response = GitHub::Launch::Services::Largerrunners::ListPoolsResponse.new(pools: [runner_without_public_ip])
      list_pools_request = GitHub::Launch::Services::Largerrunners::ListPoolsRequest.new(
        entity_id:  GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
        owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @org.global_relay_id),
        plan_owner_id: GitHub::Launch::Pbtypes::GitHub::Identity.new(global_id: @enterprise.global_relay_id),
        entity_is_private: true,
        is_public_ip_enabled: { value: false }
      )

      GitHub::Launch::Services::Largerrunners::LargerRunnersClient.any_instance
        .expects(:list_pools).with(list_pools_request).returns(Twirp::ClientResp.new(data: list_pools_response))

      runners_without_public_ip = Actions::LargerRunner.larger_runners_for(entity: @org, is_public_ip_enabled: false)
      assert_equal runners_without_public_ip.count, 1
      actual = T.must(runners_without_public_ip.first)
      assert_equal actual.name, runner_without_public_ip.name
    end
  end

  context ".get_check_runs_for_pool" do
    test "returns check runs for larger runner" do
      # stub an agent with CheckRun Id 17 (CR_kwAoEQ)
      agents = [
        GitHub::Launch::Services::Selfhostedrunners::Runner.new(id: 1, name: "PremiumRunner1_83429232", os: "linux", arch: "x64", status: "online", current_parallelism: 1, labels: @system_labels + @user_labels,
          assigned_request: GitHub::Launch::Services::Selfhostedrunners::Runner::AssignedRequest.new(job_name: "", check_run_id: "CR_kwAoEQ", external_build_id: "2770a024-2c0a-49f9-916d-a5162b0bab52,ca395085-040a-526b-2ce8-bdc85f692774"))
      ]
      list_pool_agents_response = GitHub::Launch::Services::Largerrunners::ListPoolAgentsResponse.new(agents: agents)
      GitHub::Launch::Services::Largerrunners::LargerRunnersClient.any_instance
        .expects(:list_pool_agents)
        .returns(Twirp::ClientResp.new(data: list_pool_agents_response))

      first_runner = @runners.first
      check_runs = Actions::LargerRunner.get_check_runs_for_pool(@org, pool_id: first_runner.id)
      assert_equal check_runs.count, 1

      assert_equal check_runs.first, 17
    end
  end

  context "runner group helper methods" do
    test "runner group path for org" do
      runner = build(:larger_runner, name: "foo-runner", runner_group_id: 127)
      owner_settings = Actions::OrgRunnersView.new(settings_owner: @org, current_user: @member)

      assert_equal runner.runner_group_path(owner_settings), "/organizations/#{@org.login}/settings/actions/runner-groups/127"
    end

    test "runner group path for enterprise" do
      runner = build(:larger_runner, name: "foo-runner", runner_group_id: 127)
      owner_settings = Actions::EnterpriseRunnersView.new(settings_owner: @enterprise, current_user: @member)

      assert_equal runner.runner_group_path(owner_settings), "/enterprises/#{@enterprise.slug}/settings/actions/runner-groups/127"
    end
  end

  def new_larger_runner(maximum_runners)
    image = Actions::LargerRunner::ImageKey.new(source: :Curated)
    Actions::LargerRunner.new(name: "test", runner_group_id: 1, machine_spec_id: "4-core", maximum_runners: maximum_runners, image: image)
  end

  context "maximum_runners validations" do
    test "maximum_runners between 1 and 1000" do
      image = Actions::LargerRunner::ImageKey.new(source: :Curated)
      valid_max_maximum_runners = new_larger_runner(1000)
      valid_min_maximum_runners = new_larger_runner(1)
      too_high_maximum_runners = new_larger_runner(1001)
      too_low_maximum_runners = new_larger_runner(0)

      assert valid_max_maximum_runners.valid?
      assert valid_min_maximum_runners.valid?
      refute too_high_maximum_runners.valid?
      refute too_low_maximum_runners.valid?
    end
  end

  context ".from_rpc_object" do
    [true, false].each do |all_ip_ready|
      test "is_public_ip_ready false unless all ips are ready: #{all_ip_ready}" do
        public_ip1 = GitHub::Launch::Services::Largerrunners::PublicIP.new(enabled: true, prefix: "11.22.33.44", length: 31)
        public_ip2 = GitHub::Launch::Services::Largerrunners::PublicIP.new(enabled: true, prefix: all_ip_ready ? "11.22.33.44" : "", length: 31)
        pool = GitHub::Launch::Services::Largerrunners::Pool.new(id: 1, name: "PublicIPPool", labels: ["public-ip"], state: :Ready, platform: "linux-x64", runner_group_id: 1, group_name: "", runner_count: 1, machine_spec_id: "4-core", maximum_runners: 5, public_ip_enabled: true, public_ips: Array[public_ip2, public_ip2])
        get_pool_response = GitHub::Launch::Services::Largerrunners::GetPoolResponse.new(pool: pool)

        pool = Actions::LargerRunner.from_rpc_object(get_pool_response.pool)

        refute_nil pool
        if all_ip_ready
          assert pool&.is_public_ip_ready
        else
          assert_not pool&.is_public_ip_ready
        end
      end
    end
  end
end
