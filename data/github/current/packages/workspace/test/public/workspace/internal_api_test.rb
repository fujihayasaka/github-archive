# typed: true
# frozen_string_literal: true

require "test_helper"

class Workspace::InternalApiTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    # Mimicks adding early_access_enabled group to the copilot_workspace feature flag
    enable_feature_group(:copilot_workspace, "early_access_enabled")
    Copilot::WorkspaceWaitlistSurvey.find_or_create_survey!

    disable_feature_flag(:copilot_workspace_force_no_access)
  end

  context "auto grant access to workspace via waitlist" do
    test "does not auto grant access to the workspace beta if the copilot_workspace_skip_waitlist FF is disabled" do
      disable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:workspace_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      Workspace::InternalApi.any_instance.expects(:enable_copilot_workspace).never

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does not auto grant access if the user already has access" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:workspace_enabled?).returns(true)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      Workspace::InternalApi.any_instance.expects(:enable_copilot_workspace).never

      data = Workspace::InternalApi.new(@user).response

      assert data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does not auto grant access if the user is spammy" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:workspace_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      user = create(:user, login: "spammy")
      user.stubs(:spammy?).returns(true)

      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "it does not auto grant access if the user is an EMU and the business policy is not enabled" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      business = create(:business, :enterprise_managed)
      user = business.owners.first

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
    end

    test "it auto grants access if the user is an EMU and the business policy is enabled" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      business = create(:business, :enterprise_managed)
      user = business.owners.first
      copilot_business = Copilot::Business.new(business)
      copilot_business.workspace_for_emu_enabled!
      Copilot::User.any_instance.stubs(:copilot_business).returns(copilot_business)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(true)

      data = Workspace::InternalApi.new(@user).response

      assert data[:copilot_workspace_enabled]
    end

    test "does not auto grant access if the user has trade restrictions" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:workspace_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )
      user = create(:user)
      user.stubs(:has_any_trade_restrictions?).returns(true)

      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does not grant access if their org does not have preview features enabled" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)

      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(false)

      user = create(:user)
      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(true)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does not grant access if their org does not have extensions enabled" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)

      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      user = create(:user)
      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(false)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does not auto grant access if the user is not a copilot license holder" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:workspace_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      user = create(:user)
      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(false)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "does grant access if user is a complementary Copilot Pro user such as GitHub Star, Education user, etc" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)

      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )
      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(false)
      Copilot::Public::User.any_instance.stubs(:has_free_pro_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(true)

      data = Workspace::InternalApi.new(@user).response

      assert data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "grants access but does not create an early access membership if the user is already on the waitlist" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:has_free_pro_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(true)

      survey = Copilot::WorkspaceWaitlistSurvey.find_survey
      user_on_waitlist = EarlyAccessMembership.new(
        member_id: @user.id,
        actor_id: @user.id,
        feature_slug: Copilot::WorkspaceBeta.new.feature_slug,
        survey: survey,
      )

      question = survey.questions.find_by_short_text("github_next_prerelease_terms")
      choice = question.choices.find_by_short_text("agree_github_next_prerelease_terms")
      terms_survey_answers = [{
        question_id: question.id,
        choice_id: choice.id
      }]
      user_on_waitlist.save_with_survey_answers(terms_survey_answers)

      data = Workspace::InternalApi.new(@user).response

      assert data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "returns a response when there's a ActiveRecord error granting access" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(false)

      EarlyAccessMembership.any_instance.stubs(:update!).raises(ActiveRecord::RecordInvalid)

      refute EarlyAccessMembership.exists?(member_id: @user.id)

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end

    test "grants access and creates an early access membership if the user is not on the waitlist" do
      enable_feature_flag(:copilot_workspace_skip_waitlist)
      Copilot::User.any_instance.stubs(:spark_enabled?).returns(false)
      Copilot::User.any_instance.stubs(:beta_features_github_chat_enabled?).returns(true)

      copilot_user = create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      Copilot::Public::User.any_instance.stubs(:has_paid_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:has_free_pro_access?).returns(true)
      Copilot::Public::User.any_instance.stubs(:extensions_enabled?).returns(true)

      refute EarlyAccessMembership.exists?(member_id: @user.id)

      data = Workspace::InternalApi.new(@user).response

      assert data[:copilot_workspace_enabled]
      refute data[:spark_enabled]
    end
  end unless TestEnv.test_with_all_emus?

  context "capacity dials" do
    test "excludes capacity dials without copilot_workspace_capacity_grants FF" do
      disable_feature_flag(:copilot_workspace_capacity_grants)
      create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      data = Workspace::InternalApi.new(@user).response

      refute data[:copilot_workspace_max_codespace_users]
      refute data[:copilot_workspace_max_model_users]
    end

    test "includes capacity dials without copilot_workspace_capacity_grants FF" do
      enable_feature_flag(:copilot_workspace_capacity_grants)
      create(
        :copilot_free_user,
        :y_combinator,
        user: @user,
        subscribed: true,
      )

      data = Workspace::InternalApi.new(@user).response

      assert_equal 0, data[:copilot_workspace_max_codespace_users]
      assert_equal 0, data[:copilot_workspace_max_model_users]
    end
  end

  context "feature flags" do
    Workspace::InternalApi::FEATURE_FLAGS.each do |flag|
      test "indicates when #{flag} is disabled" do
        disable_feature_flag(flag)
        create(
          :copilot_free_user,
          :y_combinator,
          user: @user,
          subscribed: true,
        )

        data = Workspace::InternalApi.new(@user).response

        refute data.dig(:feature_flags, flag)
      end

      test "indicates when #{flag} is enabled" do
        enable_feature_flag(flag)
        create(
          :copilot_free_user,
          :y_combinator,
          user: @user,
          subscribed: true,
        )

        data = Workspace::InternalApi.new(@user).response

        assert data.dig(:feature_flags, flag)
      end
    end
  end
end unless GitHub.enterprise?
