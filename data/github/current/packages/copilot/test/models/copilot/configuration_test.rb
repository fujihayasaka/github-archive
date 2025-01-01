# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotConfigurationTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  context "#public_code_suggestions" do
    {
      business: %i[allowed blocked no_policy],
      organization: %i[unconfigured allowed blocked],
      user: %i[unconfigured allowed blocked],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.public_code_suggestions.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.public_code_suggestions = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.public_code_suggestions = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "#user_telemetry" do
    {
      business: %i[disabled],
      organization: %i[disabled],
      user: %i[enabled disabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.user_telemetries.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.user_telemetry = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.user_telemetry = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "#copilot_enabled" do
    {
      business: [:enabled, :disabled, :all_organizations, :selected_organizations],
      organization: [:disabled, :enabled],
      user: [:disabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.copilot_enableds.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.copilot_enabled = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.copilot_enabled = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end

    test "standalone businesses can only enable / disable copilot" do
      config = create(
        :copilot_configuration,
        :business,
        configurable: create(:business, :enterprise_managed_business, seats_plan_type: :basic)
      )
      allowed_values = %i[enabled disabled]
      all_values = Copilot::Configuration.copilot_enableds.keys.map(&:to_sym)
      disallowed_values = all_values - allowed_values

      allowed_values.each do |value|
        config.copilot_enabled = value
        assert config.valid?, "expected #{value} to be valid for business"
      end

      disallowed_values.each do |value|
        config.copilot_enabled = value
        refute config.valid?,
          "expected #{value} to be invalid for business"
      end
    end
  end

  context "custom_models" do
    {
      business: [:unconfigured, :disabled, :enabled, :no_policy],
      organization: [:unconfigured, :disabled, :enabled, :no_policy],
      user: [:unconfigured, :disabled, :enabled, :no_policy],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.custom_models.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.custom_models = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.custom_models = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "usage_telemetry_api" do
    {
      business: [:disabled, :enabled, :no_policy],
      organization: [:disabled, :enabled],
      user: [:disabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.usage_telemetry_apis.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.usage_telemetry_api = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.usage_telemetry_api = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end

    test "standalone business" do
      config = create(
        :copilot_configuration,
        :business,
        configurable: create(:business, :enterprise_managed_business, seats_plan_type: :basic)
      )

      [:enabled, :disabled].each do |value|
        config.usage_telemetry_api = value
        assert config.valid?, "expected #{value} to be valid for a standalone business"
      end

      config.usage_telemetry_api = :no_policy
      refute config.valid?, "expected no_policy to be invalid for standalone business"
    end if TestEnv.test_with_all_emus?
  end

  context "#business?" do
    test "returns true if the configurable is a Business" do
      assert build(:copilot_configuration, :business).business?
    end

    test "returns false if the configurable is an Organization" do
      refute build(:copilot_configuration, :organization).business?
    end

    test "returns false if the configurable is a User" do
      refute build(:copilot_configuration, :user).business?
    end
  end

  context "#organization?" do
    test "returns false if the configurable is a Business" do
      refute build(:copilot_configuration, :business).organization?
    end

    test "returns true if the configurable is an Organization" do
      assert build(:copilot_configuration, :organization).organization?
    end

    test "returns false if the configurable is a User" do
      refute build(:copilot_configuration, :user).organization?
    end
  end

  context "#user?" do
    test "returns false if the configurable is a Business" do
      refute build(:copilot_configuration, :business).user?
    end

    test "returns false if the configurable is an Organization" do
      refute build(:copilot_configuration, :organization).user?
    end

    test "returns true if the configurable is a User" do
      assert build(:copilot_configuration, :user).user?
    end
  end

  test "#public_code_suggestions_configured" do
    config = create(:copilot_configuration, :user)

    config.public_code_suggestions_unconfigured!
    refute config.public_code_suggestions_configured?

    config.public_code_suggestions_allowed!
    assert config.public_code_suggestions_configured?

    config.public_code_suggestions_blocked!
    assert config.public_code_suggestions_configured?

    config = create(:copilot_configuration, :business)
    config.public_code_suggestions_no_policy!
    assert config.public_code_suggestions_configured?
  end

  context "#snippy_setting" do
    test "nil when unconfigured" do
      config = create(
        :copilot_configuration, :user,
        public_code_suggestions: "unconfigured"
      )

      assert_nil config.snippy_setting
    end

    test "false when allowed" do
      config = create(
        :copilot_configuration, :user,
        public_code_suggestions: "allowed"
      )

      assert_equal false, config.snippy_setting
    end

    test "true when blocked" do
      config = create(
        :copilot_configuration, :user,
        public_code_suggestions: "blocked"
      )

      assert_equal true, config.snippy_setting
    end
  end

  context "#copilot_for_dotcom_setting" do
    test "references the github_enterprise_feature_group setting" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      assert_equal "enabled", config.copilot_for_dotcom_setting
    end
  end

  context "#copilot_for_dotcom_configured?" do
    test "checks that github_enterprise_feature_group is not unconfigured" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      assert config.copilot_for_dotcom_configured?
    end
  end

  context "#copilot_for_dotcom_unconfigured?" do
    test "checks that github_enterprise_feature_group is unconfigured" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)

      assert config.copilot_for_dotcom_unconfigured?
    end
  end

  context "#copilot_for_dotcom_unconfigured!" do
    test "unconfigures all dotcom settings as well as github_enterprise_feature_group" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      config.copilot_for_dotcom_unconfigured!

      assert_equal "unconfigured", config.dotcom_chat
      assert_equal "unconfigured", config.github_enterprise_feature_group
      assert_equal "unconfigured", config.pr_summarizations
    end
  end

  context "#copilot_for_dotcom_enabled?" do
    test "checks that github_enterprise_feature_group is enabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      assert config.copilot_for_dotcom_enabled?
    end
  end

  context "#copilot_for_dotcom_enabled!" do
    test "enables all dotcom settings as well as github_enterprise_feature_group" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)

      config.copilot_for_dotcom_enabled!

      assert_equal "enabled", config.dotcom_chat
      assert_equal "enabled", config.github_enterprise_feature_group
      assert_equal "enabled", config.pr_summarizations
    end
  end

  context "#copilot_for_dotcom_disabled?" do
    test "checks that github_enterprise_feature_group is disabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_disabled)

      assert config.copilot_for_dotcom_disabled?
    end
  end

  context "#copilot_for_dotcom_disabled!" do
    test "disables all dotcom settings as well as github_enterprise_feature_group" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      config.copilot_for_dotcom_disabled!

      assert_equal "disabled", config.dotcom_chat
      assert_equal "disabled", config.github_enterprise_feature_group
      assert_equal "disabled", config.pr_summarizations
    end
  end

  context "#copilot_for_dotcom_no_policy?" do
    test "checks that github_enterprise_feature_group is no_policy" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_no_policy)

      assert config.copilot_for_dotcom_no_policy?
    end
  end

  context "#copilot_for_dotcom_no_policy!" do
    test "disables all dotcom settings as well as github_enterprise_feature_group" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)

      config.copilot_for_dotcom_no_policy!

      assert_equal "no_policy", config.dotcom_chat
      assert_equal "no_policy", config.github_enterprise_feature_group
      assert_equal "no_policy", config.pr_summarizations
    end
  end

  context "#bing_github_chat" do
    {
      business: %i[disabled enabled no_policy],
      organization: %i[disabled enabled],
      user: %i[disabled enabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.bing_github_chats.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.bing_github_chat = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.bing_github_chat = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "#bing_github_chat_enabled?" do
    test "checks that Bing on GitHub Chat is enabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.bing_github_chat = :enabled

      assert config.bing_github_chat_enabled?
    end
  end

  context "#bing_github_chat_enabled!" do
    test "enables Bing on GitHub Chat" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.bing_github_chat_enabled!

      assert_equal "enabled", config.bing_github_chat
      assert config.bing_github_chat_enabled?
    end
  end

  context "#bing_github_chat_disabled?" do
    test "checks that Bing on GitHub Chat is disabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.bing_github_chat = :disabled

      assert config.bing_github_chat_disabled?
    end
  end

  context "#bing_github_chat_disabled!" do
    test "disables Bing on GitHub Chat" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.bing_github_chat_disabled!

      assert_equal "disabled", config.bing_github_chat
      assert config.bing_github_chat_disabled?
    end
  end

  context "#bing_github_chat_no_policy?" do
    test "checks that Bing has no policy at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_no_policy)
      config.bing_github_chat = :no_policy

      assert config.bing_github_chat_no_policy?
    end
  end

  context "#bing_github_chat_no_policy!" do
    test "sets no policy for Bing at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.bing_github_chat_no_policy!

      assert_equal "no_policy", config.bing_github_chat
      assert config.bing_github_chat_no_policy?
    end

    test "raises a validation error at the org level" do
      org = create(:organization)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      assert_raises(ActiveRecord::RecordInvalid) do
        config.bing_github_chat_no_policy!
      end

      # reload the config to validate the change was not persisted
      config.reload

      assert_equal "disabled", config.bing_github_chat
      assert config.bing_github_chat_disabled?
    end
  end

  context "#beta_features_github_chat" do
    {
      business: %i[disabled enabled no_policy],
      organization: %i[disabled enabled],
      user: %i[disabled enabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.beta_features_github_chats.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.beta_features_github_chat = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.beta_features_github_chat = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "#beta_features_github_chat_enabled?" do
    test "checks that beta features on GitHub Chat is enabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.beta_features_github_chat = :enabled

      assert config.beta_features_github_chat_enabled?
    end
  end

  context "#beta_features_github_chat_enabled!" do
    test "enables beta features on GitHub Chat" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.beta_features_github_chat_enabled!

      assert_equal "enabled", config.beta_features_github_chat
      assert config.beta_features_github_chat_enabled?
    end
  end

  context "#beta_features_github_chat_disabled?" do
    test "checks that beta features on GitHub Chat is disabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.beta_features_github_chat = :disabled

      assert config.beta_features_github_chat_disabled?
    end
  end

  context "#beta_features_github_chat_disabled!" do
    test "disables beta features on GitHub Chat" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.beta_features_github_chat_disabled!

      assert_equal "disabled", config.beta_features_github_chat
      assert config.beta_features_github_chat_disabled?
    end
  end

  context "#beta_features_github_chat_no_policy?" do
    test "checks that beta features has no policy at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_no_policy)
      config.beta_features_github_chat = :no_policy

      assert config.beta_features_github_chat_no_policy?
    end
  end

  context "#beta_features_github_chat_no_policy!" do
    test "sets no policy for beta features at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.beta_features_github_chat_no_policy!

      assert_equal "no_policy", config.beta_features_github_chat
      assert config.beta_features_github_chat_no_policy?
    end

    test "raises a validation error at the org level" do
      org = create(:organization)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      assert_raises(ActiveRecord::RecordInvalid) do
        config.beta_features_github_chat_no_policy!
      end

      # reload the config to validate the change was not persisted
      config.reload

      assert_equal "disabled", config.beta_features_github_chat
      assert config.beta_features_github_chat_disabled?
    end
  end

  context "#user_feedback_opt_in" do
    {
      business: %i[disabled enabled no_policy],
      organization: %i[disabled enabled],
      user: %i[disabled enabled],
    }.each do |configurable_type, allowed_values|
      test "valid values for #{configurable_type}" do
        config = build(:copilot_configuration, configurable_type)

        all_values = Copilot::Configuration.user_feedback_opt_ins.keys.map(&:to_sym)
        disallowed_values = all_values - allowed_values

        allowed_values.each do |value|
          config.user_feedback_opt_in = value
          assert config.valid?,
            "expected #{value} to be valid for #{configurable_type}"
        end

        disallowed_values.each do |value|
          config.user_feedback_opt_in = value
          refute config.valid?,
            "expected #{value} to be invalid for #{configurable_type}"
        end
      end
    end
  end

  context "#user_feedback_opt_in_enabled?" do
    test "checks that user feedback is enabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.user_feedback_opt_in = :enabled

      assert config.user_feedback_opt_in_enabled?
    end
  end

  context "#user_feedback_opt_in_enabled!" do
    test "enables user feedback" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.user_feedback_opt_in_enabled!

      assert_equal "enabled", config.user_feedback_opt_in
      assert config.user_feedback_opt_in_enabled?
    end
  end

  context "#user_feedback_opt_in_disabled?" do
    test "checks that user feedback is disabled" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.user_feedback_opt_in = :disabled

      assert config.user_feedback_opt_in_disabled?
    end
  end

  context "#user_feedback_opt_in_disabled!" do
    test "disables user feedback" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_unconfigured)
      config.user_feedback_opt_in_disabled!

      assert_equal "disabled", config.user_feedback_opt_in
      assert config.user_feedback_opt_in_disabled?
    end
  end

  context "#user_feedback_opt_in_no_policy?" do
    test "checks that user feedback has no policy at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_no_policy)
      config.user_feedback_opt_in = :no_policy

      assert config.user_feedback_opt_in_no_policy?
    end
  end

  context "#user_feedback_opt_in_no_policy!" do
    test "sets no policy for user feedback at the business level" do
      config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled)
      config.user_feedback_opt_in_no_policy!

      assert_equal "no_policy", config.user_feedback_opt_in
      assert config.user_feedback_opt_in_no_policy?
    end

    test "raises a validation error at the org level when setting no policy" do
      org = create(:organization)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      assert_raises(ActiveRecord::RecordInvalid) do
        config.user_feedback_opt_in_no_policy!
      end

      # reload the config to validate the change was not persisted
      config.reload

      assert_equal "enabled", config.user_feedback_opt_in
      assert config.user_feedback_opt_in_enabled?
    end
  end

  context "#standalone_business?" do
    test "returns true for a standalone business" do
      config = create(
        :copilot_configuration,
        :business,
        configurable: create(:business, :enterprise_managed_business, seats_plan_type: :basic)
      )

      assert config.standalone_business?
    end

    test "returns false for a non-standalone business" do
      config = create(:copilot_configuration, :business)

      refute config.standalone_business?
    end
  end

  context "#cli" do
    test "standalone businesses can only enable / disable Copilot in CLI" do
      config = create(
        :copilot_configuration,
        :business,
        configurable: create(:business, :enterprise_managed_business, seats_plan_type: :basic)
      )

      allowed_values = %i[disabled enabled]
      all_values = Copilot::Configuration.clis.keys.map(&:to_sym)
      disallowed_values = all_values - allowed_values

      allowed_values.each do |value|
        config.cli = value
        assert config.valid?, "expected #{value} to be valid for business"
      end

      disallowed_values.each do |value|
        config.cli = value
        refute config.valid?,
          "expected #{value} to be invalid for business"
      end
    end
  end
end if GitHub.copilot_enabled?
