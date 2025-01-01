# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::DependencyGraphAutosubmitActionTest < GitHub::TestCase
  include DependabotAlertsEnterpriseEnablementHelper

  def autosub_product
    SecurityProduct::DependencyGraphAutosubmitAction.new(@repo).tap do |service|
      service.actions_runner_checker = @runner_checker
    end
  end

  setup do
    @runner_checker = SecurityProductsEnablement::Actions::RunnerChecker.new(@repo)

    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
    GitHub.stubs(:dependency_graph_autosubmit_action_enabled?).returns(true)
  end

  fixtures do
    @user = create(:verified_user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, :vulnerability_alerts_enabled, owner: @org)
  end

  context "#enabled?" do
    test "is false by default" do
      refute autosub_product.enabled?
    end

    test "is false if Dependency Graph becomes disabled" do
      autosub_product.on_enable(actor: @user, options: {})

      assert autosub_product.enabled?

      assert @repo.disable_dependency_graph(actor: @user)

      refute autosub_product.enabled?
    end

    test "is false if autosubmission is disabled for the instance" do
      GitHub.stubs(:dependency_graph_autosubmit_action_enabled?).returns(false)
      autosub_product.on_enable(actor: @user, options: {})

      refute autosub_product.enabled?
    end
  end

  context "#enabled_with_options?" do
    test "it is true if the feature is enabled and the options are empty" do
      autosub_product.on_enable(actor: @user, options: {})

      assert autosub_product.enabled_with_options?(options: {})
    end

    test "it is false if the feature is enabled but the labeled_runners option is given" do
      autosub_product.on_enable(actor: @user, options: {})

      refute autosub_product.enabled_with_options?(options: { labeled_runners: true })
    end

    test "it is true if the feature is enabled with labeled runners and the labeled_runners option is set" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled_with_options?(options: { labeled_runners: true })
    end

    test "it is false if the feature is enabled with labeled runners and the options are empty" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      refute autosub_product.enabled_with_options?(options: {})
    end

    test "it is false if the feature is disabled with no options given" do
      refute autosub_product.enabled_with_options?(options: {})
    end

    test "it is false if the feature is disabled and the labeled_runners option is set" do
      refute autosub_product.enabled_with_options?(options: { labeled_runners: true })
    end
  end

  context "#labeled_runners_enabled?" do
    test "is disabled by default" do
      refute autosub_product.labeled_runners_enabled?
    end

    test "is disabled when only the feature is enabled without the self-hosted option" do
      autosub_product.on_enable(actor: @user, options: {})

      refute autosub_product.labeled_runners_enabled?
    end

    test "is enabled when the feature is enabled with the self-hosted option is set" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.labeled_runners_enabled?
    end

    test "is false if autosubmission is disabled for the instance" do
      GitHub.stubs(:dependency_graph_autosubmit_action_enabled?).returns(false)
      autosub_product.on_enable(actor: @user, options: { self_hosted_runners: true })

      refute autosub_product.labeled_runners_enabled?
    end
  end

  context "can_enable?" do
    test "returns true if the feature flag is turned on and actions are enabled" do
      assert autosub_product.can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the feature flag is turned on but actions disabled" do
      @repo.disable_actions(actor: @user)

      refute autosub_product.can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the feature flag is turned on, but dependency graph is disabled" do
      if GitHub.enterprise?
        stub_dependabot_alerts_enterprise_disablement
      else
        assert @repo.disable_dependency_graph(actor: @user)
      end

      refute autosub_product.can_enable?(actor: @user, options: {}).value
    end

    test "returns false if autosubmission is disabled for the instance" do
      GitHub.stubs(:dependency_graph_autosubmit_action_enabled?).returns(false)

      refute autosub_product.can_enable?(actor: @user, options: {}).value
    end

    test "does not check Actions runners if the self-hosted runner label is not passed" do
      @runner_checker.expects(:labelled_runners_available?).never

      assert autosub_product.can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the self-hosted runner option is set but no labelled runners are available" do
      @runner_checker.expects(:labelled_runners_available?).
        with(desired_labels: ["dependency-submission"]).
        returns(false).
        once

      refute autosub_product.can_enable?(actor: @user, options: { labeled_runners: true }).value
    end

    test "returns true if the self-hosted runner option is set and labelled runners are available" do
      @runner_checker.expects(:labelled_runners_available?).
        with(desired_labels: ["dependency-submission"]).
        returns(true).
        once

      assert autosub_product.can_enable?(actor: @user, options: { labeled_runners: true }).value
    end
  end

  context "#on_enable" do
    test "it enables the product correctly" do
      autosub_product.on_enable(actor: @user, options: {})

      assert autosub_product.enabled?
      refute autosub_product.labeled_runners_enabled?
    end

    test "it supports an option for self-hosted runners" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled?
      assert autosub_product.labeled_runners_enabled?
    end

    test "it correctly transitions from self-hosted to cloud runners when the option is removed" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled?
      assert autosub_product.labeled_runners_enabled?

      autosub_product.on_enable(actor: @user, options: {})

      assert autosub_product.enabled?
      refute autosub_product.labeled_runners_enabled?
    end

    test "it correctly transitions from self-hosted to cloud runners when the option is false" do
      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled?
      assert autosub_product.labeled_runners_enabled?

      autosub_product.on_enable(actor: @user, options: { labeled_runners: false })

      assert autosub_product.enabled?
      refute autosub_product.labeled_runners_enabled?
    end

    test "it detaches its security configuration when it transitions from cloud to labeled runners" do
      security_configuration = create(
        :security_configuration,
        :disabled,
        target: @org,
        dependency_graph: "enabled",
        dependency_graph_autosubmit_action: "enabled"
      )
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @repo,
        state: "attached"
      )

      autosub_product.on_enable(actor: @user, options: { labeled_runners: false })

      assert autosub_product.enabled?
      refute autosub_product.labeled_runners_enabled?
      assert repository_security_configuration.attached?

      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled?
      assert autosub_product.labeled_runners_enabled?
      assert repository_security_configuration.reload.removed?
    end

    test "it does not detach a security configuration that allows this feature to be changed" do
      security_configuration = create(
        :security_configuration,
        :disabled,
        target: @org,
        dependency_graph: "not_set",
        dependency_graph_autosubmit_action: "not_set"
      )
      repository_security_configuration = create(
        :repository_security_configuration,
        security_configuration:,
        repository: @repo,
        state: "attached"
      )

      autosub_product.on_enable(actor: @user, options: { labeled_runners: false })

      assert autosub_product.enabled?
      refute autosub_product.labeled_runners_enabled?
      assert repository_security_configuration.attached?

      autosub_product.on_enable(actor: @user, options: { labeled_runners: true })

      assert autosub_product.enabled?
      assert autosub_product.labeled_runners_enabled?
      assert repository_security_configuration.reload.attached?
    end
  end

  context "#on_disable" do
    test "it disables the product" do
      autosub_product.on_enable(actor: @user, options: {})
      autosub_product.on_disable(actor: @user, options: {})

      refute autosub_product.enabled?
    end
  end
end
