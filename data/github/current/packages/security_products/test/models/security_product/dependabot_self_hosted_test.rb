# typed: true
# frozen_string_literal: true

require "test_helper"

class SecurityProduct::DependabotSelfHostedTest < GitHub::TestCase
  include DependabotAlertsEnterpriseEnablementHelper

  setup do
    stub_dependabot_alerts_enterprise_enablement if GitHub.enterprise?
  end

  fixtures do
    @user = create(:verified_user)
    @org = create(:organization, admin: @user)
    @repo = create(:private_repository, :vulnerability_alerts_enabled, owner: @org)
    @public_repo = create(:repository, :vulnerability_alerts_enabled, owner: @org)

    enable_feature_flag(:dependabot_on_actions)
    enable_feature_flag(:dependabot_self_hosted)
  end

  context "#enabled?" do
    test "by default is disabed" do
      refute SecurityProduct::DependabotSelfHosted.new(@repo).enabled?
    end
  end

  context "can_enable?" do
    test "it returns false if the feature flag is not turned on" do
      disable_feature_flag(:dependabot_self_hosted)

      refute SecurityProduct::DependabotSelfHosted.new(@repo).can_enable?(actor: @user, options: {}).value
    end

    test "returns true if the feature flag is turned on and actions are enabled" do
      @repo.enable_vulnerability_updates(actor: @user)

      assert SecurityProduct::DependabotSelfHosted.new(@repo).can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the feature flag is turned on and actions are blocked by policy" do
      @repo.disable_vulnerability_alerts(actor: @user)

      # TODO: Find out how to verify actions policy status
      @repo.disable_actions(actor: @user)

      refute SecurityProduct::DependabotSelfHosted.new(@repo).can_enable?(actor: @user, options: {}).value
    end

    test "returns false if the repo is public" do
      refute SecurityProduct::DependabotSelfHosted.new(@public_repo).can_enable?(actor: @user, options: {}).value
    end
  end

  context "#on_enable" do
    test "it enables the config option" do
      SecurityProduct::DependabotSelfHosted.new(@repo).on_enable(actor: @user, options: {})

      assert SecurityProduct::DependabotSelfHosted.new(@repo).enabled?
    end

    test "it does not enable the config option on public repos" do
      SecurityProduct::DependabotSelfHosted.new(@public_repo).on_enable(actor: @user, options: {})

      refute SecurityProduct::DependabotSelfHosted.new(@public_repo).enabled?
    end
  end

  context "#on_disable" do
    test "it disables the product" do
      SecurityProduct::DependabotSelfHosted.new(@repo).on_enable(actor: @user, options: {})
      SecurityProduct::DependabotSelfHosted.new(@repo).on_disable(actor: @user, options: {})

      refute SecurityProduct::DependabotSelfHosted.new(@repo).enabled?
    end
  end
end
