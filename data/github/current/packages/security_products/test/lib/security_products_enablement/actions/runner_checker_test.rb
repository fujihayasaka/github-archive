# typed: true
# frozen_string_literal: true

require "actions-runner-admin"
require "test_helper"
require "test_helpers/launch/self_hosted_runners_helper"
require "test_helpers/launch/runner_groups_helper"
require "test_helpers/launch/setup_tenant_helper"

class SecurityProductsEnablement::Actions::RunnerCheckerTest < GitHub::TestCase
  include Launch::SelfHostedRunnersHelper

  fixtures do
    GitHub::Enterprise.ensure_business!
    @user = create(:user)
    @owner = create(:organization)
    @owner.add_member(@user)
    @repository = create(:private_repository, owner: @owner)
  end

  setup do
    @checker = SecurityProductsEnablement::Actions::RunnerChecker.new(@repository)
  end

  context "#labelled_runners_available?" do
    #large runners are not available in GHES
    test "returns true if a large cloud hosted runner exists with the correct label", skip_enterprise: true do
      @owner.onboard_larger_runners(actor: @user)
      business = create :business, organizations: [@owner]

      Actions::LargerRunner.stubs(:larger_runners_for).returns(
        [
          Actions::Runner.new(id: 1, name: "A runner", os: "linux", status: "idle",
            labels: [GitHub::ActionsRunnerAdmin::Api::V1::RunnerLabel.new(id: 1, name: "code-scanning", type: "user")])
        ]
      )
      assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns true if there are runners in the runner group have the correct label" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [Actions::RunnerGroup.new(id: 1, name: "Runner Group", runners: [self_hosted_runner_with_labels("code-scanning")])]
      )

      assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns true if any of the runner scale sets have the correct label" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [Actions::RunnerGroup.new(id: 1, name: "Runner Group",
          runner_scale_sets: [runner_scale_set_with_labels("code-scanning")])]
      )

      assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns true if any of the runners assigned to the repo have correct label" do
      mock_list_runners(owner: @repository, status: 200, response:
        GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [self_hosted_runner_with_labels("code-scanning")], total_runners: 1))

      assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns true if any of the runner scale sets assigned to a personal repo have the correct label" do
      Actions::RunnerScaleSet.stubs(:for_entity).returns([runner_scale_set_with_labels("code-scanning")])

      assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns false if none of the available runners has the correct label" do
      @owner.onboard_larger_runners(actor: @user)
      Actions::LargerRunner.stubs(:larger_runners_for).returns(
        [
          Actions::Runner.new(id: 1, name: "A runner", os: "linux", status: "idle",
            labels: [GitHub::ActionsRunnerAdmin::Api::V1::RunnerLabel.new(id: 1, name: "not-code-scanning", type: "user")])
        ]
      )

      mock_list_runners(owner: @repository, status: 200,
        response: GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(
          runners: [self_hosted_runner_with_labels("not-code-scanning")], total_runners: 1)
        )

      Actions::RunnerGroup.stubs(:for_entity).returns(
        [
          Actions::RunnerGroup.new(id: 1, name: "Runner Group 1", runners: [self_hosted_runner_with_labels("not-code-scanning")]),
          Actions::RunnerGroup.new(id: 2, name: "Runner Group 2", runner_scale_sets: [runner_scale_set_with_labels("not-code-scanning")])
        ]
      )

      Actions::RunnerScaleSet.stubs(:for_entity).returns(
        [runner_scale_set_with_labels("not-code-scanning")]
      )

      refute @checker.labelled_runners_available?(desired_labels: ["code-scanning"])
    end

    test "returns true when multiple labels are desired and there are runners available with all desired labels" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [
          Actions::RunnerGroup.new(id: 1, name: "Runner Group 1", runners: [self_hosted_runner_with_labels("dependency-graph", "dependency-submission", "dependency")]),
        ]
      )
      assert @checker.labelled_runners_available?(desired_labels: %w(dependency-graph dependency-submission))
    end

    test "returns true when multiple labels are desired and there are runners available with all desired labels, regardless of order" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [
          Actions::RunnerGroup.new(id: 1, name: "Runner Group 1", runners: [self_hosted_runner_with_labels("dependency-submission", "dependency-graph", "dependency")]),
        ]
      )
      assert @checker.labelled_runners_available?(desired_labels: %w(dependency-graph dependency-submission))
    end

    test "returns true when multiple, repeated labels are desired and there are runners available with all desired labels" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [
          Actions::RunnerGroup.new(id: 1, name: "Runner Group 1", runners: [self_hosted_runner_with_labels("dependency-submission", "dependency-graph", "dependency")]),
        ]
      )
      assert @checker.labelled_runners_available?(desired_labels: %w(dependency-submission dependency-graph dependency-graph))
    end

    test "returns false when multiple labels are desired but no runner matches all of them" do
      Actions::RunnerGroup.stubs(:for_entity).returns(
        [
          Actions::RunnerGroup.new(id: 1, name: "Runner Group 1", runners: [self_hosted_runner_with_labels("dependency-graph", "dependency", "submission")]),
          Actions::RunnerGroup.new(id: 2, name: "Runner Group 2", runners: [self_hosted_runner_with_labels("dependency-submission")]),
        ]
      )
      refute @checker.labelled_runners_available?(desired_labels: %w(dependency-graph dependency-submission))
    end

    context "label caching" do
      #large runners are not available in GHES
      test "cloud hosted runners will only be checked once across multiple calls", skip_enterprise: true do
        @owner.onboard_larger_runners(actor: @user)
        business = create :business, organizations: [@owner]

        Actions::LargerRunner.expects(:larger_runners_for).returns(
          [
            Actions::Runner.new(id: 1, name: "A runner", os: "linux", status: "idle",
              labels: [GitHub::ActionsRunnerAdmin::Api::V1::RunnerLabel.new(id: 1, name: "code-scanning", type: "user")])
          ]
        ).once

        assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])

        refute @checker.labelled_runners_available?(desired_labels: ["dependency-submission"])
      end

      test "runner groups will only be checked once across multiple calls" do
        Actions::RunnerGroup.stubs(:for_entity).returns(
          [Actions::RunnerGroup.new(id: 1, name: "Runner Group", runners: [self_hosted_runner_with_labels("code-scanning")])]
        ).once

        assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])

        refute @checker.labelled_runners_available?(desired_labels: ["dependency-submission"])
      end

      test "runner group scale sets will only be checked once across multiple calls" do
        Actions::RunnerGroup.stubs(:for_entity).returns(
          [Actions::RunnerGroup.new(id: 1, name: "Runner Group",
            runner_scale_sets: [runner_scale_set_with_labels("code-scanning")])]
        ).once

        assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])

        refute @checker.labelled_runners_available?(desired_labels: ["dependency-submission"])
      end

      test "assigned runners will only be checked once across multiple calls" do
        mock_list_runners(owner: @repository, status: 200, only_once: true, response:
          GitHub::Launch::Services::Selfhostedrunners::ListRunnersResponse.new(runners: [self_hosted_runner_with_labels("code-scanning")], total_runners: 1))

        assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])

        refute @checker.labelled_runners_available?(desired_labels: ["dependency-submission"])
      end

      test "assigned runner group scale sets will only be checked once across multiple calls" do
        Actions::RunnerScaleSet.stubs(:for_entity).returns([runner_scale_set_with_labels("code-scanning")]).once

        assert @checker.labelled_runners_available?(desired_labels: ["code-scanning"])

        refute @checker.labelled_runners_available?(desired_labels: ["dependency-submission"])
      end
    end
  end

  private

  def self_hosted_runner_with_labels(*labels)
    runner_labels = labels.map { |label| self_hosted_runner_label(label: label) }
    GitHub::Launch::Services::Selfhostedrunners::Runner.new(labels: runner_labels)
  end

  def self_hosted_runner_label(label:)
    GitHub::Launch::Services::Selfhostedrunners::Label.new(name: label)
  end

  def runner_scale_set_with_labels(*labels)
    runner_labels = labels.map { |label| runner_scale_set_label(label: label) }
    GitHub::Launch::Services::Runnerscalesets::RunnerScaleSet.new(labels: runner_labels)
  end

  def runner_scale_set_label(label:)
    GitHub::Launch::Services::Runnerscalesets::Label.new(name: label)
  end
end
