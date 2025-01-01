# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotUsersInstrumentationDetailsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @copilot_monthly_product_uuid = T.let(create(:billing_product_uuid, :copilot, billing_cycle: :month), T.nilable(::Billing::ProductUUID))
    @copilot_yearly_product_uuid = T.let(create(:billing_product_uuid, :copilot, billing_cycle: :year), T.nilable(::Billing::ProductUUID))
    @plan_subscription = T.let(create(:billing_plan_subscription, :zuora), T.nilable(::Billing::PlanSubscription))
    @user = T.let(T.must(@plan_subscription).user, T.nilable(User))
  end

  context "copilot_user_details" do
    test "default returns UNKNOWN string" do
      user = create(:user)

      copilot_user = Copilot::User.new(user)

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_DISABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_DISABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :NO_SUBSCRIPTION,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "technical preview user after grace period" do
      Copilot::User.any_instance.stubs(:is_technical_preview_user?).returns(true)
      user = create(:user)

      copilot_user = Copilot::User.new(user)

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_DISABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_DISABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: true,
        is_trial: false,
        subscription_plan: :NO_SUBSCRIPTION,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "net user with monthly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_monthly_product_uuid,
             free_trial_ends_on: nil
            )
      copilot_user = Copilot::User.new(T.must(@user))

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :MONTHLY,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "returns trial monthly for copilot user" do
      copilot_monthly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :month)
      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid,
             plan_subscription: plan_subscription,
             subscribable: copilot_monthly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )

      copilot_user = Copilot::User.new(user)
      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: true,
        subscription_plan: :MONTHLY,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "net user with yearly subscription" do
      create(:billing_subscription_item, :paid,
             plan_subscription: @plan_subscription,
             subscribable: @copilot_yearly_product_uuid,
             free_trial_ends_on: nil
            )
      copilot_user = Copilot::User.new(T.must(@user))

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :YEARLY,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "returns trial yearly for copilot user" do
      copilot_yearly_product_uuid = create(:billing_product_uuid, :copilot, billing_cycle: :year)

      plan_subscription = create(:billing_plan_subscription, :zuora)
      user = plan_subscription.user

      create(:billing_subscription_item, :paid,
             plan_subscription: plan_subscription,
             subscribable: copilot_yearly_product_uuid,
             free_trial_ends_on: 10.days.from_now
            )

      copilot_user = Copilot::User.new(user)
      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: true,
        subscription_plan: :YEARLY,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "free user" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::ENGAGED_OSS.name,
        subscribed: true,
      )
      copilot_user = Copilot::User.new(user)

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_UNCONFIGURED,
          desktop_setting: :DESKTOP_UNCONFIGURED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_ENABLED,
          github_chat_setting: :GITHUB_CHAT_UNCONFIGURED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_UNCONFIGURED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_UNCONFIGURED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :ENGAGED_OSS,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :NO_SUBSCRIPTION,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "copilot business seat" do
      enable_feature_flag(:copilot_desktop)

      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_ENABLED,
          desktop_setting: :DESKTOP_ENABLED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_DISABLED,
          github_chat_setting: :GITHUB_CHAT_ENABLED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_ENABLED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_ENABLED,
          telemetry_configuration: :DISABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :NO_SUBSCRIPTION,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end

    test "copilot business seat from special org" do
      enable_feature_flag(:copilot_desktop)

      ::User.any_instance.stubs(:organization_ids).returns([Copilot::GITHUB_ORG_ID])
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)

      expected = {
        copilot_user_settings: {
          cli_setting: :CLI_ENABLED,
          desktop_setting: :DESKTOP_ENABLED,
          editor_preview_features_setting: :EDITOR_PREVIEW_FEATURES_UNCONFIGURED,
          a_chat_setting: :A_CHAT_UNCONFIGURED,
          af_setting: :AF_UNCONFIGURED,
          g_chat_setting: :G_CHAT_UNCONFIGURED,
          o1_setting: :O1_UNCONFIGURED,
          o3_setting: :O3_UNCONFIGURED,
          of_setting: :OF_UNCONFIGURED,
          off_setting: :OFF_UNCONFIGURED,
          copilot_extensions_setting: :COPILOT_EXTENSIONS_UNCONFIGURED,
          custom_models_setting: :CUSTOM_MODELS_UNCONFIGURED,
          editor_chat_setting: :EDITOR_CHAT_ENABLED,
          github_chat_bing_access_setting: :GITHUB_CHAT_BING_ACCESS_DISABLED,
          github_chat_setting: :GITHUB_CHAT_ENABLED,
          mobile_chat_setting: :MOBILE_CHAT_ENABLED,
          pr_summarizations_setting: :PR_SUMMARIZATIONS_ENABLED,
          private_docs_setting: :PRIVATE_DOCS_UNCONFIGURED,
          snippy_setting: :SNIPPY_ENABLED,
          telemetry_configuration: :ENABLED,
          overages_setting: :OVERAGES_UNCONFIGURED,
        },
        free_access_type: :FREE_USER_NOT_PRESENT,
        is_technical_preview_user: false,
        is_trial: false,
        subscription_plan: :NO_SUBSCRIPTION,
        trust_tier: nil,
      }

      assert_equal expected, copilot_user.copilot_user_details
    end
  end

  context "copilot_free_user_type" do
    test "unknown" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      assert_equal :FREE_USER_NOT_PRESENT, copilot_user.copilot_free_user_type
    end

    test "ENGAGED_OSS" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::ENGAGED_OSS.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :ENGAGED_OSS, copilot_user.copilot_free_user_type
    end

    test "EDUCATIONAL" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::EDUCATIONAL.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :EDUCATIONAL, copilot_user.copilot_free_user_type
    end

    test "GITHUB_STAR" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::GITHUB_STAR.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :GITHUB_STAR, copilot_user.copilot_free_user_type
    end

    test "MS_MVP" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::MS_MVP.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :MS_MVP, copilot_user.copilot_free_user_type
    end

    test "WORKSHOP" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::WORKSHOP.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :WORKSHOP, copilot_user.copilot_free_user_type
    end

    test "Y_COMBINATOR" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::Y_COMBINATOR.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :Y_COMBINATOR, copilot_user.copilot_free_user_type
    end

    test "COMPLIMENTARY_ACCESS" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::COMPLIMENTARY_ACCESS.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :COMPLIMENTARY_ACCESS, copilot_user.copilot_free_user_type
    end

    test "TECHNICAL_PREVIEW_EXTENSION" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :TECHNICAL_PREVIEW_EXTENSION, copilot_user.copilot_free_user_type
    end

    test "HEY_GITHUB" do
      user = create(:user)
      create(
        :copilot_free_user,
        user: user,
        free_user_type: Copilot::FreeUser::HEY_GITHUB.name,
      )
      copilot_user = Copilot::User.new(user)
      assert_equal :HEY_GITHUB, copilot_user.copilot_free_user_type
    end
  end
end if GitHub.copilot_enabled?
