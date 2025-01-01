# typed: true
# frozen_string_literal: true

require "test_helper"
require "turboscan"

module CodeScanning
  class ToolConfigurationGroupTest < GitHub::TestCase
    fixtures do
      @repository = create :repository
    end

    test "can generate a slug a workflow" do
      refute_nil ::CodeScanning::ToolConfigurationGroup.slug configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML, workflow_path: ".github/workflows/test.yml")
    end

    context "scan events" do
      test "produces correct events for managed analyses with default branch" do
        group = ::CodeScanning::ToolConfigurationGroup.new repository: @repository, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED), categories: [], overall_status: 0, workflow: nil, tool_name: "CodeQL"
        branches = [@repository.default_branch]
        expected = { "push" => { "branches" => branches }, "pull_request" => { "branches" => branches } }
        assert_equal expected, group.scan_events
      end

      test "produces correct events for managed analyses with protected branch" do
        create :protected_branch, repository: @repository, name: "protected-branch"
        branches = [@repository.default_branch, "protected-branch"]
        group = ::CodeScanning::ToolConfigurationGroup.new repository: @repository, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED), categories: [], overall_status: 0, workflow: nil, tool_name: "CodeQL"
        expected = { "push" => { "branches" => branches }, "pull_request" => { "branches" => branches } }
        assert_equal expected, group.scan_events
      end

      test "produces correct events for managed analyses with protected branch pattern" do
        create :protected_branch, repository: @repository, name: "protected-branches-*"
        branches = [@repository.default_branch, "protected-branches-*"]
        group = ::CodeScanning::ToolConfigurationGroup.new repository: @repository, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED), categories: [], overall_status: 0, workflow: nil, tool_name: "CodeQL"
        expected = { "push" => { "branches" => branches }, "pull_request" => { "branches" => branches } }
        assert_equal expected, group.scan_events
      end

      test "doesn't include branch twice if it's the default branch and a protected branch" do
        create :protected_branch, repository: @repository, name: @repository.default_branch
        branches = [@repository.default_branch]
        group = ::CodeScanning::ToolConfigurationGroup.new repository: @repository, configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED), categories: [], overall_status: 0, workflow: nil, tool_name: "CodeQL"
        expected = { "push" => { "branches" => branches }, "pull_request" => { "branches" => branches } }
        assert_equal expected, group.scan_events
      end
    end

    context "#build_groups" do
      test "creates one object for each configuration group type represented in the tool's categories" do
        categories = [
          ::Turboscan::Proto::CategoryStatus.new(
            workflow_run_id: 1,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
          ),
          ::Turboscan::Proto::CategoryStatus.new(
            workflow_run_id: 2,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
          ),
          ::Turboscan::Proto::CategoryStatus.new(
            workflow_run_id: 3,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED),
          ),
        ]

        groups = CodeScanning::ToolConfigurationGroup.build_groups(
          repository: @repository,
          tool: Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: categories),
          messages: CodeScanning::Status::Messages.new("CodeQL" => []),
          workflows: {}
        )

        # The two API groups are considered equal since their workflow path is the same
        assert_equal 2, groups.length

        T.must(categories.first.configuration_group).workflow_path = "some/other/path"
        groups = CodeScanning::ToolConfigurationGroup.build_groups(
          repository: @repository,
          tool: Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: categories),
          messages: CodeScanning::Status::Messages.new("CodeQL" => []),
          workflows: {}
        )

        # The two API groups are considered different since their workflow paths are different
        assert_equal 3, groups.length
      end

      test "overall status of a group just considers messages for the relevant category" do
        categories = [
          ::Turboscan::Proto::CategoryStatus.new(
            workflow_run_id: 1,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_API),
            configuration_hash: "abc"
          ),
          ::Turboscan::Proto::CategoryStatus.new(
            workflow_run_id: 2,
            configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_MANAGED),
            configuration_hash: "def"
          ),
        ]

        messages = CodeScanning::Status::Messages.new("CodeQL" => [
          CodeScanning::Status::Error.new(
            title: "ATTENTION message",
            level: CodeScanning::Status::ATTENTION,
            message: "attention!",
            category: categories.first,
          ),
          CodeScanning::Status::Error.new(
            title: "DANGER message",
            level: CodeScanning::Status::DANGER,
            message: "danger!",
            category: categories.second,
          ),
        ])

        groups = CodeScanning::ToolConfigurationGroup.build_groups(
          repository: @repository,
          tool: Turboscan::Proto::ToolStatus.new(name: "CodeQL", categories: categories),
          messages: messages,
          workflows: {}
        )

        assert_equal 2, groups.length

        api_group = groups.find do |g|
          g.configuration_group.delivery_origin == :DELIVERY_ORIGIN_API
        end
        refute_nil api_group

        managed_group = groups.find do |g|
          g.configuration_group.delivery_origin == :DELIVERY_ORIGIN_MANAGED
        end
        refute_nil managed_group

        assert_equal CodeScanning::Status::ATTENTION, T.must(api_group).overall_status, "unexpected overall_status"
        assert_equal CodeScanning::Status::DANGER, T.must(managed_group).overall_status, "unexpected overall_status"
      end
    end

    context "#schedules" do
      test "handles empty schedules" do
        group = ::CodeScanning::ToolConfigurationGroup.new(
          repository: @repository,
          configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML),
          categories: [],
          overall_status: 0,
          workflow: CodeScanning::Status::Workflow.new(
            path: "path.yml",
            name: "CodeQL",
            schedule: [],
            events: nil,
          ),
          tool_name: "CodeQL",
        )
        assert_nil group.schedules
      end
    end

    test "handles valid schedules" do
      group = ::CodeScanning::ToolConfigurationGroup.new(
        repository: @repository,
        configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML),
        categories: [],
        overall_status: 0,
        workflow: CodeScanning::Status::Workflow.new(
          path: "path.yml",
          name: "CodeQL",
          schedule: [
            { "cron" => "*/5 * * * *" },
          ],
          events: nil,
        ),
        tool_name: "CodeQL",
      )
      assert_equal ["*/5 * * * *"], group.schedules
    end

    test "filters invalid schedules" do
      group = ::CodeScanning::ToolConfigurationGroup.new(
        repository: @repository,
        configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML),
        categories: [],
        overall_status: 0,
        workflow: CodeScanning::Status::Workflow.new(
          path: "path.yml",
          name: "CodeQL",
          schedule: [
            { "foo" => "*/5 * * * *" },
            { "cron" => 5 },
            { "cron" => {} },
          ],
          events: nil,
        ),
        tool_name: "CodeQL",
      )
      assert_nil group.schedules
    end

    test "handles invalid schedule property" do
      group = ::CodeScanning::ToolConfigurationGroup.new(
        repository: @repository,
        configuration_group: ::Turboscan::Proto::ConfigurationGroup.new(delivery_origin: :DELIVERY_ORIGIN_YML),
        categories: [],
        overall_status: 0,
        workflow: CodeScanning::Status::Workflow.new(
          path: "path.yml",
          name: "CodeQL",
          schedule: { "cron" => "*/5 * * * *" },
          events: nil,
        ),
        tool_name: "CodeQL",
      )
      assert_nil group.schedules
    end
  end
end
