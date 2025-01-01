# typed: true
# frozen_string_literal: true

require "test_helper"

class UserFeatureFlagMethodsTest < GitHub::TestCase
  include HydroTestHelpers
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
    @edge_feature = create(:feature_with_flipper, :opt_in)
  end

  setup do
    Flipper.enable_percentage_of_actors(@edge_feature.flipper_feature.name, 100)
  end

  context "#enable_feature_preview", skip_enterprise: true do
    test "does not add user to non-beta feature" do
      feature = "something-random"
      @user.disable_feature(feature)

      refute @user.enable_feature_preview(feature)
      refute @user.feature_preview_enabled?(feature)
    end

    test "enrolls a user in an Edge feature" do
      assert_difference -> { @edge_feature.enrollments.count } do
        @user.enable_feature_preview(@edge_feature)
      end
      assert @user.feature_preview_enabled?(@edge_feature.slug)
    end
  end

  context "#disable_feature_preview", skip_enterprise: true do
    test "unenrolls a user from an Edge feature" do
      @user.disable_feature_preview(@edge_feature)
      refute @user.feature_preview_enabled?(@edge_feature.slug)
    end

    test "returns falsey when given a non-beta feature", skip_enterprise: true do
      feature = "something-random"
      refute @user.disable_feature_preview(feature)
    end
  end

  context "#feature_preview_enabled?", skip_enterprise: true do
    test "false when feature is not an eligible beta feature" do
      refute @user.feature_preview_enabled?("something-random")
      assert_dogstats_increment 1, "beta_feature.enabled_check", tags: ["feature:something-random", "feature_found:false"]
      assert_dogstats_timing(1, "beta_feature.enabled_check.duration", tags: ["feature:something-random"])
    end

    test "works for Edge features" do
      @user.enable_feature_preview(@edge_feature)
      assert @user.feature_preview_enabled?(@edge_feature.slug)

      @user.disable_feature_preview(@edge_feature)
      refute @user.feature_preview_enabled?(@edge_feature.slug)
      assert_dogstats_increment 2, "beta_feature.enabled_check", tags: ["feature:#{@edge_feature.slug}", "feature_found:true"]
      assert_dogstats_timing(2, "beta_feature.enabled_check.duration", tags: ["feature:#{@edge_feature.slug}"])
    end

    test "is false for opt-in Edge feature if user loses (Flipper) access" do
      @user.enable_feature_preview(@edge_feature)
      assert @user.feature_preview_enabled?(@edge_feature.slug)

      @edge_feature.flipper_feature.disable
      @user.send(:reset_feature_preview_memoization)
      refute @user.feature_preview_enabled?(@edge_feature.slug)
      assert_dogstats_increment 2, "beta_feature.enabled_check", tags: ["feature:#{@edge_feature.slug}", "feature_found:true"]
      assert_dogstats_timing(2, "beta_feature.enabled_check.duration", tags: ["feature:#{@edge_feature.slug}"])
    end

    test "is false for opt-out Edge feature if user loses (Flipper) access" do
      feature = create(:feature_with_flipper, :opt_out)
      feature.flipper_feature.enable(@user)
      assert @user.feature_preview_enabled?(feature.slug)

      feature.flipper_feature.disable(@user)
      @user.send(:reset_feature_preview_memoization)
      refute @user.feature_preview_enabled?(feature.slug)
      assert_dogstats_increment 2, "beta_feature.enabled_check", tags: ["feature:#{feature.slug}", "feature_found:true"]
      assert_dogstats_timing(2, "beta_feature.enabled_check.duration", tags: ["feature:#{feature.slug}"])
    end

    test "records number of times called per feature" do
      user = build(:user)

      user.feature_preview_enabled?("something")
      user.feature_preview_enabled?("something")
      user.feature_preview_enabled?("something-else")

      assert_equal(user.checked_feature_previews.dig("something", :times_checked), 2)
      assert_equal(user.checked_feature_previews.dig("something-else", :times_checked), 1)
    end
  end

  context "#checked_feature_previews", skip_enterprise: true do
    test "returns a hash of checked FeaturePreview with stats" do
      user = build(:user)

      user.feature_preview_enabled?("something")

      assert_equal(user.checked_feature_previews.dig("something", :times_checked), 1)
      refute(user.checked_feature_previews.dig("something", :enabled))
    end

    test "returns an empty hash if no FeaturePreviews have been checked" do
      user = build(:user)

      assert_equal(user.checked_feature_previews, {})
    end
  end

  context "#microsoft_mvp?", skip_enterprise: true do
    test "returns false if user doesn't have a coupon" do
      user = create(:user)
      refute user.coupon
      refute user.microsoft_mvp?
    end

    test "returns false if user coupon is not MVP coupon" do
      user = create(:user)
      coupon = create(:coupon, group: "internal")
      user.redeem_coupon(coupon)

      assert user.coupon
      refute user.microsoft_mvp?
    end

    test "returns true if user coupon is  MVP coupon" do
      user = create(:user)
      coupon = create(:coupon, code: "MVP-c2c241b")
      user.redeem_coupon(coupon)

      assert user.coupon
      assert user.microsoft_mvp?
    end
  end

  context "#patsv2_enabled?" do
    test "returns false if the organization isn't opted into PATs v2" do
      org = create(:organization)

      refute_predicate org, :patsv2_enabled?
    end

    test "returns true if the organization is opted into PATs v2" do
      org = create(:organization, admin: create(:user))
      org.opt_in_programmatic_access_tokens(actor: org.admin)

      assert_predicate org, :patsv2_enabled?
    end

    test "returns false if the neither the business nor the org is opted into PATs v2" do
      org = create(:enterprise_linked_organization)
      business = org.business

      refute_predicate business, :patsv2_enabled?
      refute_predicate org, :patsv2_enabled?
    end

    test "returns true if the business owning the organization is opted into PATs v2" do
      org = create(:enterprise_linked_organization, admin: create(:user))
      business = org.business

      business.opt_in_programmatic_access_tokens(actor: org.admin)
      org.reload

      assert_predicate business, :patsv2_enabled?
      assert_predicate org, :patsv2_enabled?
    end

    test "enabling on the org does not enable on the business" do
      org = create(:enterprise_linked_organization)
      business = org.business

      org.opt_in_programmatic_access_tokens(actor: org.admin)

      refute_predicate business, :patsv2_enabled?
      assert_predicate org, :patsv2_enabled?
    end
  end

  context "#actor_tenant" do
    test "returns no tenant when not in Proxima mode" do
      if !TestEnv.test_in_multitenancy_mode?
        user = create(:user)
        result = user.actor_tenant
        assert_nil result
      end
    end

    test "returns tenant info when in Proxima mode" do
      if TestEnv.test_in_multitenancy_mode?
        user = create(:user)
        result = user.actor_tenant
        tenant = user.enterprise_managed_business
        assert_equal tenant.id, result.id
        assert_equal tenant.name, result.name
      end
    end

    test "returns no tenant info when in Proxima mode and business is missing" do
      if TestEnv.test_in_multitenancy_mode?
        user = User.create(login: "user-without-business-#{SecureRandom.hex(12)}")
        assert_nil user.enterprise_managed_business
        result = user.actor_tenant
        assert_nil result
      end
    end
  end

  context "#sire_hubber" do
    test "returns true when member is part of the sire-hubbers group" do
      if TestEnv.test_in_multitenancy_mode?
        emu_user = create :emu
        business = @user.enterprise_managed_business
        organization_admin = create :emu, business: business
        org = create :organization, business: business, admin: organization_admin

        StafftoolsRole.create(name: "sire")
        sire_hubber = create :emu, business: business
        sire_hubber_identity = sire_hubber.external_identities.first
        jit_group = create :external_group, business: business, display_name: "sire-hubbers"
        sire_jit_team = create :team, organization: org
        ExternalGroupTeam.create(external_group: jit_group, team: sire_jit_team)
        # this will update the user's stafftools role
        ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: sire_hubber_identity)

        GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
        GitHub::CurrentTenant.set(business)
      else
        sire_hubber = create :staff_admin_user, login: "sire"
        team = create(:team, organization: github_org, name: "sire-hubbers")
        team.add_member(sire_hubber)
      end

      assert sire_hubber.security_incident_response_access?
    end

    test "returns false when member is staff but is not a sire hubber" do
      if TestEnv.test_in_multitenancy_mode?
        emu_user = create :emu
        business = @user.enterprise_managed_business
        organization_admin = create :emu, business: business
        org = create :organization, business: business, admin: organization_admin

        StafftoolsRole.create(name: "support")
        support_hubber = create :emu, business: business
        support_hubber_identity = support_hubber.external_identities.first
        jit_group = create :external_group, business: business, display_name: "stafftools-support-jit"
        support_jit_team = create :team, organization: org
        ExternalGroupTeam.create(external_group: jit_group, team: support_jit_team)
        # this will update the user's stafftools role
        ExternalIdentityGroupMembership.create(external_group: jit_group, external_identity: support_hubber_identity)

        GitHub::CurrentTenant.stubs(:stafftools_tenant?).returns(true)
        GitHub::CurrentTenant.set(business)
      else
        support_hubber = create :staff_admin_user, login: "sire"
      end

      refute support_hubber.security_incident_response_access?
    end
  end

  context "#flipper_actor_names" do
    test "from_flipper_actor_name_user" do
      user = create :user
      # assert that getting the user from the flipper actor name returns the same user
      assert_equal user, User.from_flipper_actor_name(user.flipper_actor_name)
      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal user.flipper_id, user.flipper_actor_name
      # assert that that flipper actor name is the display login
      assert_equal user.display_login, user.flipper_actor_name
    end

    test "from_flipper_actor_name_bot" do
      bot = create :bot
      # assert that getting the user from the flipper actor name returns the same user
      assert_equal bot, Bot.from_flipper_actor_name(bot.flipper_actor_name)
      # assert that the flipper actor name has been overridden and is not the same as the flipper id
      refute_equal bot.flipper_id, bot.flipper_actor_name
      # assert that that flipper actor name is the display login
      assert_equal bot.display_login, bot.flipper_actor_name
    end
  end
end
