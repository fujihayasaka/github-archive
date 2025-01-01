# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::DependabotOnActionsTest < GitHub::TestCase
  include DependabotAlertsEnterpriseEnablementHelper

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
  end

  fixtures do
    @user = create(:verified_user)
    @org = create(:organization, admin: @user)
    @repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)

    enable_feature_flag(:dependabot_on_actions)
  end

  context "#enabled?" do
    test "by default is disabled" do
      refute SecurityProduct::DependabotOnActions.new(@repo).enabled?
    end

    test "returns true if enabled" do
      SecurityProduct::DependabotOnActions.new(@repo).on_enable(actor: @user, options: {})

      assert SecurityProduct::DependabotOnActions.new(@repo).enabled?
    end

    test "returns false when enabled but Actions is disabled" do
      SecurityProduct::DependabotOnActions.new(@repo).on_enable(actor: @user, options: {})
      @repo.disable_actions(actor: @user)

      refute SecurityProduct::DependabotOnActions.new(@repo).enabled?
    end
  end

  context "can_enable?" do
    test "it returns false if the feature flag is not turned on" do
      disable_feature_flag(:dependabot_on_actions)

      refute SecurityProduct::DependabotOnActions.new(@repo).can_enable?(actor: @user, options: {}).value
    end

    test "returns true if the feature flag is turned on and actions are enabled" do
      @repo.enable_vulnerability_updates(actor: @user)

      assert SecurityProduct::DependabotOnActions.new(@repo).can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the feature flag is turned on and actions are blocked by policy" do
      @repo.disable_actions(actor: @user)

      refute SecurityProduct::DependabotOnActions.new(@repo).can_enable?(actor: @user, options: {}).value
    end
  end

  context "#on_enable" do
    test "it enables the product" do
      SecurityProduct::DependabotOnActions.new(@repo).on_enable(actor: @user, options: {})

      assert SecurityProduct::DependabotOnActions.new(@repo).enabled?
    end

    # test "it enables actions if they are not enabled" do
    #   SecurityProduct::DependabotOnActions.new(@repo).on_enable(actor: @user, options: {})

    #   assert @repo.config.actions.enabled?
    # end
  end

  context "#on_disable" do
    test "it disables the product" do
      SecurityProduct::DependabotOnActions.new(@repo).on_enable(actor: @user, options: {})
      SecurityProduct::DependabotOnActions.new(@repo).on_disable(actor: @user, options: {})

      refute SecurityProduct::DependabotOnActions.new(@repo).enabled?
    end
  end
end
