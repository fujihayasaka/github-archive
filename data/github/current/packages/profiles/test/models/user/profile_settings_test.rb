# typed: true
# frozen_string_literal: true

require "test_helper"

class UserProfileSettingsTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "#activity_overview_enabled?" do
    test "true when user setting has been enabled" do
      @user.profile_settings.activity_overview_enabled = true
      assert_predicate @user.profile_settings, :activity_overview_enabled?
    end

    test "false when user setting has been disabled" do
      @user.profile_settings.activity_overview_enabled = false
      refute_predicate @user.profile_settings, :activity_overview_enabled?
    end
  end

  context "activity_overview_enabled=(value)" do
    test "doesn't store anything when the user is not persisted" do
      user = User.new
      Profiles::Kv.store.expects(:set).never
      user.profile_settings.activity_overview_enabled = false
    end

    test "enables setting when set to true" do
      @user.profile_settings.activity_overview_enabled = true
      assert_predicate @user.profile_settings, :activity_overview_enabled?
    end

    test "enables setting when set to '1'" do
      @user.profile_settings.activity_overview_enabled = "1"
      assert_predicate @user.profile_settings, :activity_overview_enabled?
    end

    test "disables setting when set to false" do
      @user.profile_settings.activity_overview_enabled = false
      refute_predicate @user.profile_settings, :activity_overview_enabled?
    end

    test "disables setting when set to '0'" do
      @user.profile_settings.activity_overview_enabled = "0"
      refute_predicate @user.profile_settings, :activity_overview_enabled?
    end

    test "instruments beta enrollment when setting enabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :ENROLL,
        feature: :ORG_SCOPED_ACTIVITY,
      }

      @user.profile_settings.activity_overview_enabled = true

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end

    test "instruments beta unenrollment when setting disabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :UNENROLL,
        feature: :ORG_SCOPED_ACTIVITY,
      }

      @user.profile_settings.activity_overview_enabled = false

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end
  end

  context "pro_badge_enabled=(value)" do
    test "doesn't store anything when the user is not persisted" do
      user = User.new
      Profiles::Kv.store.expects(:set).never
      user.profile_settings.pro_badge_enabled = false
    end

    test "enables setting when set to true" do
      @user.profile_settings.pro_badge_enabled = true
      assert_predicate @user.profile_settings, :pro_badge_enabled?
    end

    test "enables setting when set to '1'" do
      @user.profile_settings.pro_badge_enabled = "1"
      assert_predicate @user.profile_settings, :pro_badge_enabled?
    end

    test "disables setting when set to false" do
      @user.profile_settings.pro_badge_enabled = false
      refute_predicate @user.profile_settings, :pro_badge_enabled?
    end

    test "disables setting when set to '0'" do
      @user.profile_settings.pro_badge_enabled = "0"
      refute_predicate @user.profile_settings, :pro_badge_enabled?
    end

    test "instruments beta enrollment when setting enabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :ENROLL,
        feature: :pro_badge,
      }

      @user.profile_settings.pro_badge_enabled = true

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end

    test "instruments beta unenrollment when setting disabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :UNENROLL,
        feature: :pro_badge,
      }

      @user.profile_settings.pro_badge_enabled = false

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end
  end

  context "nasa_badge_enabled=(value)" do
    test "sets achievements to disabled when setting is disabled" do
      badge = create(:profile_highlight, user: @user, highlight_type: "nasa_2020", hidden: false)

      @user.profile_settings.nasa_badge_enabled = false

      refute_predicate @user.profile_settings, :achievements_enabled?
      refute @user.profile_settings.async_achievements_enabled?.sync
      refute_predicate @user.profile_settings, :nasa_badge_enabled?
      assert_predicate badge.reload, :hidden?
    end
  end

  context "achievements_enabled=(value)" do
    test "sets nasa and acv to disabled when setting is disabled" do
      @user.profile_settings.achievements_enabled = false

      refute_predicate @user.profile_settings, :achievements_enabled?
      refute @user.profile_settings.async_achievements_enabled?.sync
      refute_predicate @user.profile_settings, :nasa_badge_enabled?
      refute_predicate @user.profile_settings, :acv_badge_enabled?
    end

    test "doesn't store anything when the user is not persisted" do
      user = User.new
      Profiles::Kv.store.expects(:set).never
      user.profile_settings.achievements_enabled = false
    end

    test "enables setting when set to true" do
      @user.profile_settings.achievements_enabled = true

      assert_predicate @user.profile_settings, :achievements_enabled?
      assert @user.profile_settings.async_achievements_enabled?.sync
    end

    test "enables setting when set to '1'" do
      @user.profile_settings.achievements_enabled = "1"

      assert_predicate @user.profile_settings, :achievements_enabled?
      assert @user.profile_settings.async_achievements_enabled?.sync
    end

    test "disables setting when set to false" do
      @user.profile_settings.achievements_enabled = false

      refute_predicate @user.profile_settings, :achievements_enabled?
      refute @user.profile_settings.async_achievements_enabled?.sync
    end

    test "disables setting when set to '0'" do
      @user.profile_settings.achievements_enabled = "0"

      refute_predicate @user.profile_settings, :achievements_enabled?
      refute @user.profile_settings.async_achievements_enabled?.sync
    end
  end

  context "acv_badge_enabled=(value)" do
    test "sets achievements enabled disabled when setting is disabled" do
      @user.profile_settings.acv_badge_enabled = false

      refute_predicate @user.profile_settings, :acv_badge_enabled?
      refute_predicate @user.profile_settings, :achievements_enabled?
      refute @user.profile_settings.async_achievements_enabled?.sync
    end

    test "doesn't store anything when the user is not persisted" do
      user = User.new
      Profiles::Kv.store.expects(:set).never
      user.profile_settings.acv_badge_enabled = false
    end

    test "enables setting when set to true" do
      @user.profile_settings.acv_badge_enabled = true
      assert_predicate @user.profile_settings, :acv_badge_enabled?
    end

    test "enables setting when set to '1'" do
      @user.profile_settings.acv_badge_enabled = "1"
      assert_predicate @user.profile_settings, :acv_badge_enabled?
    end

    test "disables setting when set to false" do
      @user.profile_settings.acv_badge_enabled = false
      refute_predicate @user.profile_settings, :acv_badge_enabled?
    end

    test "disables setting when set to '0'" do
      @user.profile_settings.acv_badge_enabled = "0"
      refute_predicate @user.profile_settings, :acv_badge_enabled?
    end

    test "instruments beta enrollment when setting enabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :ENROLL,
        feature: :acv_badge,
      }

      @user.profile_settings.acv_badge_enabled = true

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end

    test "instruments beta unenrollment when setting disabled", skip_enterprise: true do
      message = {
        actor: Hydro::EntitySerializer.user(@user),
        action: :UNENROLL,
        feature: :acv_badge,
      }

      @user.profile_settings.acv_badge_enabled = false

      assert_hydro_published(message, schema: "github.v1.BetaFeatureEnrollmentEvent")
    end
  end

  context "show_private_contribution_count? and async_show_private_contribution_count?" do
    test "false when preference is not specified" do
      refute_predicate @user.profile_settings, :show_private_contribution_count?
      refute @user.profile_settings.async_show_private_contribution_count?.sync
    end

    test "false when user is not saved" do
      user = User.new
      refute_predicate user.profile_settings, :show_private_contribution_count?
      refute user.profile_settings.async_show_private_contribution_count?.sync
    end

    test "false when preference is set to false" do
      @user.profile_settings.show_private_contribution_count = false
      refute_predicate @user.profile_settings, :show_private_contribution_count?
      refute @user.profile_settings.async_show_private_contribution_count?.sync
    end

    test "true when preference is set to true" do
      @user.profile_settings.show_private_contribution_count = true
      assert_predicate @user.profile_settings, :show_private_contribution_count?
      assert @user.profile_settings.async_show_private_contribution_count?.sync
    end

    test "false when Profiles::Kv.store throws an error" do
      @user.profile_settings.show_private_contribution_count = true

      e = StandardError.new("nope")
      result = GitHub::Result.new { raise e }
      Profiles::Kv.store.stubs(:get).returns(result)

      refute_predicate @user.profile_settings, :show_private_contribution_count?
    end
  end

  context "show_private_contribution_count=(value)" do
    test "doesn't store anything when the user is not persisted" do
      user = User.new
      Profiles::Kv.store.expects(:set).never
      user.profile_settings.show_private_contribution_count = false
    end

    test "is true when set to `true`" do
      @user.profile_settings.show_private_contribution_count = true
      assert_predicate @user.profile_settings, :show_private_contribution_count?
    end

    test "is true when set to '1'" do
      @user.profile_settings.show_private_contribution_count = "1"
      assert_predicate @user.profile_settings, :show_private_contribution_count?
    end

    test "is false when set to `false`" do
      @user.profile_settings.show_private_contribution_count = false
      refute_predicate @user.profile_settings, :show_private_contribution_count?
    end

    test "is false when set to '0'" do
      @user.profile_settings.show_private_contribution_count = "0"
      refute_predicate @user.profile_settings, :show_private_contribution_count?
    end

    test "instruments showing private contributions" do
      events = subscribe("user.show_private_contributions_count")

      @user.profile_settings.show_private_contribution_count = true

      expected_payload = {
        user:      @user.login,
        user_id:   @user.id,
        actor:     @user.login,
        actor_id:  @user.id,
      }
      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end

    test "instruments hiding private contributions count" do
      events = subscribe("user.hide_private_contributions_count")

      @user.profile_settings.show_private_contribution_count = false

      expected_payload = {
        user:      @user.login,
        user_id:   @user.id,
        actor:     @user.login,
        actor_id:  @user.id,
      }
      assert event = events.pop, "expected an instrumentation event"
      assert_equal expected_payload, event.payload
    end
  end
end
