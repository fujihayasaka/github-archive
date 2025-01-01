# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersSettingsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:copilot_extensibility_policy_override].disable
    GitHub.flipper[:copilot_dotcom_chat_ci_and_cb].enable
    GitHub.flipper[:copilot_a_chat].enable
    GitHub.flipper[:copilot_g_chat].enable
  end

  context "copilot_for_business_enabled?" do
    test "always false for blank users" do
      copilot_user = Copilot::User.new(create(:user))
      refute copilot_user.copilot_for_business_enabled?
      refute Copilot::User.new(create(:user)).copilot_for_business_enabled?
    end

    test "returns true for cfb users" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_for_business_enabled?
    end

    test "returns true for cfb standalone users" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats

      seat = seat_assignment.seats.first
      user = seat.assigned_user

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_for_business_enabled?
    end if TestEnv.test_with_all_emus?
  end

  test "configuration defaults" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)
    copilot_user.ensure_configuration!
    configuration = Copilot::Configuration.find_by!(configurable: user)

    assert_subset_hash({
      "user_telemetry" => "enabled",
      "max_seats" => 0,
      "cli" => "unconfigured",
    }, configuration.attributes)
  end

  context "public code suggestions" do
    test "setting creates configuration record" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      assert_changes -> { Copilot::Configuration.count }, from: 0, to: 1 do
        copilot_user.allow_public_code_suggestions!
      end
    end

    test "user defaults to snippy unconfigured" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      refute copilot_user.allow_public_code_suggestions?
      refute copilot_user.block_public_code_suggestions?
      refute copilot_user.public_code_suggestions_configured?
      assert_equal "unconfigured", copilot_user.snippy_setting
    end

    test "user defaults to chat disabled" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      refute copilot_user.chat_enabled?
      assert copilot_user.chat_disabled?
      assert_equal "disabled", copilot_user.chat_setting
    end

    test "enabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)
      copilot_user = Copilot::User.new(user)

      configuration = create(:copilot_configuration, configurable: user)

      refute copilot_user.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_unconfigured?

      copilot_user.block_public_code_suggestions!

      assert configuration.reload.public_code_suggestions_blocked?

      assert copilot_user.public_code_suggestions_configured?
      assert copilot_user.block_public_code_suggestions?
      refute copilot_user.allow_public_code_suggestions?
      assert_equal "enabled", copilot_user.snippy_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_blocked",
        tags: ["type:user"],
      ).length
    end

    test "disabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)
      copilot_user = Copilot::User.new(user)

      configuration = create(:copilot_configuration, configurable: user)

      refute copilot_user.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_unconfigured?

      copilot_user.allow_public_code_suggestions!

      assert configuration.reload.public_code_suggestions_allowed?

      assert copilot_user.public_code_suggestions_configured?
      refute copilot_user.block_public_code_suggestions?
      assert copilot_user.allow_public_code_suggestions?
      assert_equal "disabled", copilot_user.snippy_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_allowed",
        tags: ["type:user"],
      ).length
    end

  end

  context "multiple organizations" do
    test "chat enabled if part of multiple organizations and at least one is enabled" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      user.reload
      assert Copilot::User.new(user).chat_enabled?
    end

    test "chat disabled if part of multiple organizations and none are enabled" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      user.reload
      refute Copilot::User.new(user).chat_enabled?
    end

    test "chat disabled if part of multiple enterprises and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).enable_chat!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).disable_chat!

      user.reload
      refute Copilot::User.new(user).chat_enabled?
    end
  end

  context "Permissive copilot chat settings" do
    test "chat enabled if part of multiple organizations and one is enabled and one is not configured" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      user.reload
      assert Copilot::User.new(user).chat_enabled?
    end

    test "chat enabled if part of multiple organizations and all are allowed" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).enable_chat!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).enable_chat!

      user.reload
      assert Copilot::User.new(user).chat_enabled?
    end

    test "chat disabled if part of multiple enterprises and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).enable_chat!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).disable_chat!

      user.reload
      refute Copilot::User.new(user).chat_enabled?
    end
  end

  context "CLI settings" do
    test "CLI enabled if part of multiple organizations and one is enabled and one is not configured" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).cli_enabled!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)

      user.reload
      assert Copilot::User.new(user).cli_enabled?
    end

    test "CLI enabled if part of multiple organizations and all are allowed" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Organization.new(org).cli_enabled!

      org2 = create(:business_organization)
      org2.add_member user
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).cli_enabled!

      user.reload
      assert Copilot::User.new(user).cli_enabled?
    end

    test "CLI disabled if part of multiple enterprises and one is disabled" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).cli_enabled!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      user.reload
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Business.new(business2).cli_disabled!

      user.reload
      refute Copilot::User.new(user).cli_enabled?
    end

    test "CLI enabled if part of multiple enterprises but has a seat in only one of them" do
      business = create(:business)
      user = create(:user)
      org = create(:business_organization)
      business.add_organization org
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      Copilot::Business.new(business).cli_enabled!

      business2 = create(:business)
      org2 = create(:business_organization)
      org2.add_member user
      business2.add_organization org2
      copilot_business = Copilot::Business.new(business2)
      copilot_business.enable_copilot_for_all_organizations!
      copilot_business.cli_disabled!

      user.reload
      assert Copilot::User.new(user).cli_enabled?
    end

    test "CLI enabled if user is just a CFI user" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      copilot_user = Copilot::User.new(user)
      assert copilot_user.has_cfi_access?

      assert copilot_user.cli_enabled?
      refute copilot_user.cli_disabled?
      assert_equal "enabled", copilot_user.cli_setting
    end

    context "when disabled" do
      test "and user does not have copilot at all" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)

        refute copilot_user.cli_enabled?
      end

      test "and a member of any business in which the user has a seat has cli disabled" do
        business = create(:business)
        user = create(:user)
        org = create(:business_organization)
        business.add_organization org
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).cli_disabled!

        business2 = create(:business)
        org2 = create(:business_organization)
        org2.add_member user
        business2.add_organization org2
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Business.new(business2).cli_enabled!

        user.reload
        assert Copilot::User.new(user).cli_disabled?
      end

      test "only evaluates business in which the user has a seat" do
        business = create(:business)
        user = create(:user)
        org = create(:business_organization)
        business.add_organization org
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).cli_disabled!

        business2 = create(:business)
        org2 = create(:business_organization)
        org2.add_member user
        business2.add_organization org2
        copilot_business = Copilot::Business.new(business2)
        copilot_business.enable_copilot_for_all_organizations!
        copilot_business.cli_enabled!

        user.reload
        assert Copilot::User.new(user).cli_disabled?
      end

      test "is not disabled when user is a member of multiple orgs and one is disabled" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).cli_enabled!

        org2 = create(:business_organization)
        org2.add_member user
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Organization.new(org2).cli_disabled!

        user.reload
        refute Copilot::User.new(user).cli_disabled?
        assert Copilot::User.new(user).cli_enabled?
      end

      test "and a member of multiple orgs and all are disabled" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).cli_disabled!

        org2 = create(:business_organization)
        org2.add_member user
        user.reload
        create(:copilot_seat, organization: org2, assigned_user: user)
        Copilot::Organization.new(org2).cli_disabled!

        user.reload
        assert Copilot::User.new(user).cli_disabled?
        refute Copilot::User.new(user).cli_enabled?
      end
    end
  end

  context "#copilot_for_dotcom" do
    test "is enabled when copilot_for_dotcom_enabled?" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      create(:copilot_configuration, :copilot_for_dotcom_enabled, configurable: user)

      assert_equal "enabled", copilot_user.copilot_for_dotcom
      assert_equal "enabled", copilot_user.dotcom_chat_setting
      assert_equal "enabled", copilot_user.pr_summarizations_setting
    end

    test "is disabled when copilot_for_dotcom_disabled?" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      create(:copilot_configuration, :copilot_for_dotcom_disabled, configurable: user)
      assert_equal "disabled", copilot_user.dotcom_chat_setting
      assert_equal "disabled", copilot_user.copilot_for_dotcom
      assert_equal "disabled", copilot_user.pr_summarizations_setting
    end

    test "is unconfigured otherwise" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      create(:copilot_configuration, :copilot_for_dotcom_unconfigured, configurable: user)

      assert_equal "unconfigured", copilot_user.copilot_for_dotcom
      assert_equal "unconfigured", copilot_user.dotcom_chat_setting
      assert_equal "unconfigured", copilot_user.pr_summarizations_setting
    end
  end

  context "#copilot_for_dotcom_configured?" do
    context "when part of a configured org" do
      test "is true" do
        user = create(:user)
        org = create(:organization)
        org.add_member(user)
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!

        assert copilot_user.copilot_for_dotcom_configured?
        assert copilot_user.dotcom_chat_configured?
        assert copilot_user.pr_summarizations_configured?
      end
    end

    context "when not part of a configured org" do
      test "is if their config is not unconfigured" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :copilot_for_dotcom_enabled, configurable: user)

        assert copilot_user.copilot_for_dotcom_configured?
        assert copilot_user.dotcom_chat_configured?
        assert copilot_user.pr_summarizations_configured?
      end

      test "is false if their config is unconfigured" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :copilot_for_dotcom_unconfigured, configurable: user)

        refute copilot_user.copilot_for_dotcom_configured?
        refute copilot_user.dotcom_chat_configured?
        refute copilot_user.pr_summarizations_configured?
      end
    end
  end

  context "#dotcom_chat_enabled?" do
    context "when has_ci_access?" do
      test "is true" do
        user = create(:user)
        create(:copilot_free_user, user: user, subscribed: true)
        copilot_user = Copilot::User.new(user)
        assert copilot_user.dotcom_chat_enabled?
      end
    end
  end

  context "#copilot_for_dotcom_enabled?" do
    context "when part of a disabled business" do
      test "is false" do
        business = create(:business)
        org = create(:organization, business: business)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).copilot_for_dotcom_disabled!
        copilot_user = Copilot::User.new(user)

        refute copilot_user.copilot_for_dotcom_enabled?
        refute copilot_user.dotcom_chat_enabled?
        refute copilot_user.pr_summarizations_enabled?
      end
    end

    context "when no business disables it and an org enables it" do
      test "is true" do
        business = create(:business)
        org = create(:organization, business: business)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Business.new(business).copilot_for_dotcom_no_policy!
        copilot_user = Copilot::User.new(user)

        assert copilot_user.copilot_for_dotcom_enabled?
        assert copilot_user.dotcom_chat_enabled?
        assert copilot_user.pr_summarizations_enabled?
      end
    end

    context "when orgs disable it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)
        copilot_user = Copilot::User.new(user)

        refute copilot_user.copilot_for_dotcom_enabled?
        refute copilot_user.dotcom_chat_enabled?
        refute copilot_user.pr_summarizations_enabled?
      end
    end

    context "when not part of an org" do
      test "references the user config" do
        user = create(:user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert copilot_user.copilot_for_dotcom_enabled?
        assert copilot_user.dotcom_chat_enabled?
        assert copilot_user.pr_summarizations_enabled?
      end
    end
  end

  context "copilot_for_dotcom_enabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

      copilot_user.copilot_for_dotcom_enabled!

      assert config.reload.dotcom_chat_enabled?
      assert config.reload.pr_summarizations_enabled?
    end
  end

  context "#copilot_for_dotcom_disabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

        assert copilot_user.copilot_for_dotcom_disabled?
        assert copilot_user.pr_summarizations_disabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).copilot_for_dotcom_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        refute copilot_user.copilot_for_dotcom_disabled?
        refute copilot_user.dotcom_chat_disabled?
        refute copilot_user.pr_summarizations_disabled?
      end
    end

    context "when not part of an org" do
      test "references the user config" do
        user = create(:user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert copilot_user.copilot_for_dotcom_disabled?
        # Todo: uncomment after db migration to update default to unconfigured.
        # assert copilot_user.dotcom_chat_disabled?
        assert copilot_user.pr_summarizations_disabled?
      end
    end
  end

  context "copilot_for_dotcom_disabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

      copilot_user.copilot_for_dotcom_disabled!

      assert config.reload.dotcom_chat_disabled?
      assert config.reload.pr_summarizations_disabled?
    end
  end

  context "dotcom_chat_enabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

      copilot_user.dotcom_chat_enabled!

      assert config.reload.dotcom_chat_enabled?
    end
  end

  context "#dotcom_chat_disabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).disable_dotcom_chat!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

        assert copilot_user.dotcom_chat_disabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).dotcom_chat_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        refute copilot_user.dotcom_chat_disabled?
      end
    end
  end

  context "dotcom_chat_disabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

      copilot_user.disable_dotcom_chat!

      assert config.reload.dotcom_chat_disabled?
    end
  end

  context "mobile chat" do
    test "is disabled if any business is disabled" do
      user = create(:user)
      biz1 = create(:business)
      biz2 = create(:business)
      org1 = create(:business_organization, business: biz1)
      org2 = create(:business_organization, business: biz2)
      org1.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).enable_mobile_chat!
      Copilot::Business.new(biz2).disable_mobile_chat!
      user.reload

      assert Copilot::User.new(user).mobile_chat_disabled?
    end

    test "is enabled if all businesses are enabled" do
      user = create(:user)
      biz1 = create(:business)
      biz2 = create(:business)
      org1 = create(:business_organization, business: biz1)
      org2 = create(:business_organization, business: biz2)
      org1.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).enable_mobile_chat!
      Copilot::Business.new(biz2).enable_mobile_chat!
      user.reload

      assert Copilot::User.new(user).mobile_chat_enabled?
    end

    test "is enabled if all orgs are enabled" do
      user = create(:user)
      biz = create(:business)
      org = create(:business_organization, business: biz)
      org2 = create(:organization)
      org.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      refute Copilot::User.new(user).mobile_chat_enabled?

      Copilot::Business.new(biz).mobile_chat_no_policy!
      Copilot::Organization.new(org).enable_mobile_chat!

      Copilot::Organization.new(org2).enable_mobile_chat!
      user.reload

      assert Copilot::User.new(user).mobile_chat_enabled?
    end

    test "is disabled if any org is disabled" do
      user = create(:user)
      org = create(:organization)
      org2 = create(:organization)
      org.add_member(user)
      org2.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org).enable_mobile_chat!
      Copilot::Organization.new(org2).disable_mobile_chat!
      user.reload

      refute Copilot::User.new(user).mobile_chat_enabled?
      assert Copilot::User.new(user).mobile_chat_disabled?
    end

    test "not enabled for user, org or biz" do
      user = create(:user)
      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      create(:copilot_seat, organization: org, assigned_user: user)

      assert Copilot::User.new(user).mobile_chat_disabled?
    end

    test "is always enabled for CFI" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      copilot_user = Copilot::User.new(user)
      assert copilot_user.has_cfi_access?

      assert copilot_user.mobile_chat_enabled?
    end
  end

  context "Bing in dotcom chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_enable!

      assert Copilot::User.new(user).bing_github_chat_enabled?
      refute Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is enabled if part of multiple business orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_enable!

      assert Copilot::User.new(user).bing_github_chat_enabled?
      refute Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is disabled even if the user belongs to a Copilot Business enterprise" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_disabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!

      assert Copilot::User.new(user).bing_github_chat_disabled?
      refute Copilot::User.new(user).bing_github_chat_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_enable!
      Copilot::Organization.new(other_org).bing_github_chat_enable!

      assert Copilot::User.new(user).bing_github_chat_enabled?
      refute Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!

      refute Copilot::User.new(user).bing_github_chat_enabled?
      assert Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is disabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_enable!
      Copilot::Organization.new(other_org).bing_github_chat_disable!

      refute Copilot::User.new(user).bing_github_chat_enabled?
      assert Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).bing_github_chat_disable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).bing_github_chat_disable!

      refute Copilot::User.new(user).bing_github_chat_enabled?
      assert Copilot::User.new(user).bing_github_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).bing_github_chat_disable!
      Copilot::Organization.new(other_org).bing_github_chat_disable!

      refute Copilot::User.new(user).bing_github_chat_enabled?
      assert Copilot::User.new(user).bing_github_chat_disabled?
    end
  end

  context "a_chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_enabled!

      assert Copilot::User.new(user).a_chat_enabled?
      refute Copilot::User.new(user).a_chat_disabled?
    end

    test "is enabled if part of multiple business orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_enabled!

      assert Copilot::User.new(user).a_chat_enabled?
      refute Copilot::User.new(user).a_chat_disabled?
    end

    test "is disabled even if the user belongs to a Copilot Business enterprise" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_disabled!

      assert Copilot::User.new(user).a_chat_disabled?
      refute Copilot::User.new(user).a_chat_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).a_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_enabled!
      Copilot::Organization.new(other_org).a_chat_enabled!

      assert Copilot::User.new(user).a_chat_enabled?
      refute Copilot::User.new(user).a_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_enabled!
      Copilot::Business.new(other_biz).a_chat_disabled!

      refute Copilot::User.new(user).a_chat_enabled?
      assert Copilot::User.new(user).a_chat_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled and the other is enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_enabled!
      Copilot::Organization.new(other_org).a_chat_disabled!

      assert Copilot::User.new(user).a_chat_enabled?
      refute Copilot::User.new(user).a_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).a_chat_disabled!
      Copilot::Business.new(other_biz).a_chat_disabled!

      refute Copilot::User.new(user).a_chat_enabled?
      assert Copilot::User.new(user).a_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).a_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).a_chat_disabled!
      Copilot::Organization.new(other_org).a_chat_disabled!

      refute Copilot::User.new(user).a_chat_enabled?
      assert Copilot::User.new(user).a_chat_disabled?
    end
  end

  context "g_chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_enabled!

      assert Copilot::User.new(user).g_chat_enabled?
      refute Copilot::User.new(user).g_chat_disabled?
    end

    test "is enabled if part of multiple business orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_enabled!

      assert Copilot::User.new(user).g_chat_enabled?
      refute Copilot::User.new(user).g_chat_disabled?
    end

    test "is disabled even if the user belongs to a Copilot Business enterprise" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_disabled!

      assert Copilot::User.new(user).g_chat_disabled?
      refute Copilot::User.new(user).g_chat_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).g_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_enabled!
      Copilot::Organization.new(other_org).g_chat_enabled!

      assert Copilot::User.new(user).g_chat_enabled?
      refute Copilot::User.new(user).g_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_enabled!
      Copilot::Business.new(other_biz).g_chat_disabled!

      refute Copilot::User.new(user).g_chat_enabled?
      assert Copilot::User.new(user).g_chat_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled and the other is enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_enabled!
      Copilot::Organization.new(other_org).g_chat_disabled!

      assert Copilot::User.new(user).g_chat_enabled?
      refute Copilot::User.new(user).g_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).g_chat_disabled!
      Copilot::Business.new(other_biz).g_chat_disabled!

      refute Copilot::User.new(user).g_chat_enabled?
      assert Copilot::User.new(user).g_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).g_chat_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).g_chat_disabled!
      Copilot::Organization.new(other_org).g_chat_disabled!

      refute Copilot::User.new(user).g_chat_enabled?
      assert Copilot::User.new(user).g_chat_disabled?
    end
  end

  context "o1" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_enabled!

      assert Copilot::User.new(user).o1_enabled?
      refute Copilot::User.new(user).o1_disabled?
    end

    test "is enabled if part of multiple business orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_enabled!

      assert Copilot::User.new(user).o1_enabled?
      refute Copilot::User.new(user).o1_disabled?
    end

    test "is disabled even if the user belongs to a Copilot Business enterprise" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_disabled!

      assert Copilot::User.new(user).o1_disabled?
      refute Copilot::User.new(user).o1_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).o1_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_enabled!
      Copilot::Organization.new(other_org).o1_enabled!

      assert Copilot::User.new(user).o1_enabled?
      refute Copilot::User.new(user).o1_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_enabled!
      Copilot::Business.new(other_biz).o1_disabled!

      refute Copilot::User.new(user).o1_enabled?
      assert Copilot::User.new(user).o1_disabled?
    end

    test "is enabled if part of multiple orgs and one is disabled and the other is enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_enabled!
      Copilot::Organization.new(other_org).o1_disabled!

      assert Copilot::User.new(user).o1_enabled?
      refute Copilot::User.new(user).o1_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).o1_disabled!
      Copilot::Business.new(other_biz).o1_disabled!

      refute Copilot::User.new(user).o1_enabled?
      assert Copilot::User.new(user).o1_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).o1_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).o1_disabled!
      Copilot::Organization.new(other_org).o1_disabled!

      refute Copilot::User.new(user).o1_enabled?
      assert Copilot::User.new(user).o1_disabled?
    end
  end

  context "Beta features in dotcom chat" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).beta_features_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).beta_features_github_chat_enable!

      assert Copilot::User.new(user).beta_features_github_chat_enabled?
      refute Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).beta_features_github_chat_enable!
      Copilot::Organization.new(other_org).beta_features_github_chat_enable!

      assert Copilot::User.new(user).beta_features_github_chat_enabled?
      refute Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).beta_features_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).beta_features_github_chat_disable!

      refute Copilot::User.new(user).beta_features_github_chat_enabled?
      assert Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is disabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).beta_features_github_chat_enable!
      Copilot::Organization.new(other_org).beta_features_github_chat_disable!

      refute Copilot::User.new(user).beta_features_github_chat_enabled?
      assert Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).beta_features_github_chat_disable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).beta_features_github_chat_disable!

      refute Copilot::User.new(user).beta_features_github_chat_enabled?
      assert Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).beta_features_github_chat_disable!
      Copilot::Organization.new(other_org).beta_features_github_chat_disable!

      refute Copilot::User.new(user).beta_features_github_chat_enabled?
      assert Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is enabled if user has copilot business license and has opted into beta features" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).beta_features_github_chat_enable!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).beta_features_github_chat_enable!

      assert Copilot::User.new(user).beta_features_github_chat_enabled?
      refute Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is disabled if user has copilot business license and has not opted into beta features" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!

      refute Copilot::User.new(user).beta_features_github_chat_enabled?
      assert Copilot::User.new(user).beta_features_github_chat_disabled?
    end

    test "is enabled for user with copilot individual license" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      assert Copilot::User.new(user).has_cfi_access?
      assert Copilot::User.new(user).beta_features_github_chat_enabled?
      refute Copilot::User.new(user).beta_features_github_chat_disabled?
    end
  end

  context "user feedback opt in setting" do
    test "is enabled if part of multiple enterprises and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).enable_user_feedback!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).enable_user_feedback!

      assert Copilot::User.new(user).user_feedback_opt_in_enabled?
      refute Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is enabled if part of multiple business orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_business!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).enable_user_feedback!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).enable_user_feedback!

      assert Copilot::User.new(user).user_feedback_opt_in_enabled?
      refute Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is disabled even if the user belongs to a Copilot Business enterprise" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_business!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).enable_user_feedback!
      Copilot::Business.new(other_biz).copilot_for_dotcom_disabled!
      Copilot::Business.new(other_biz).disable_user_feedback!

      assert Copilot::User.new(user).user_feedback_opt_in_disabled?
      refute Copilot::User.new(user).user_feedback_opt_in_enabled?
    end

    test "is enabled if part of multiple orgs and all are enabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).enable_user_feedback!
      Copilot::Organization.new(other_org).enable_user_feedback!

      assert Copilot::User.new(user).user_feedback_opt_in_enabled?
      refute Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is disabled if part of multiple enterprises and one is disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).enable_user_feedback!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).disable_user_feedback!

      refute Copilot::User.new(user).user_feedback_opt_in_enabled?
      assert Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is disabled if part of multiple orgs and one is disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).enable_user_feedback!
      Copilot::Organization.new(other_org).disable_user_feedback!

      refute Copilot::User.new(user).user_feedback_opt_in_enabled?
      assert Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is disabled if part of multiple enterprises and all are disabled" do
      user = create(:user)

      biz = create(:business)
      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_biz = create(:business)
      other_org = create(:business_organization, business: other_biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Business.new(biz).copilot_plan_enterprise!
      Copilot::Business.new(other_biz).copilot_plan_enterprise!

      Copilot::Business.new(biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(biz).disable_user_feedback!
      Copilot::Business.new(other_biz).copilot_for_dotcom_enabled!
      Copilot::Business.new(other_biz).disable_user_feedback!

      refute Copilot::User.new(user).user_feedback_opt_in_enabled?
      assert Copilot::User.new(user).user_feedback_opt_in_disabled?
    end

    test "is disabled if part of multiple orgs and all are disabled" do
      user = create(:user)

      biz = create(:business)
      Copilot::Business.new(biz).copilot_plan_enterprise!

      # set no dotcom chat policy at the enterprise level
      Copilot::Business.new(biz).copilot_for_dotcom_no_policy!

      org = create(:business_organization, business: biz)
      org.add_member(user)

      other_org = create(:business_organization, business: biz)
      other_org.add_member(user)

      user.reload
      create(:copilot_seat, organization: org, assigned_user: user)
      create(:copilot_seat, organization: other_org, assigned_user: user)

      Copilot::Organization.new(org).disable_user_feedback!
      Copilot::Organization.new(other_org).disable_user_feedback!

      refute Copilot::User.new(user).user_feedback_opt_in_enabled?
      assert Copilot::User.new(user).user_feedback_opt_in_disabled?
    end
  end

  context "pr_summarizations_enabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

      copilot_user.pr_summarizations_enabled!

      assert config.reload.pr_summarizations_enabled?
    end
  end

  context "#pr_summarizations_disabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).pr_summarizations_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

        assert copilot_user.pr_summarizations_disabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).pr_summarizations_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_for_dotcom_disabled, configurable: user)

        refute copilot_user.pr_summarizations_disabled?
      end
    end
  end

  context "pr_summarizations_disabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_for_dotcom_enabled, configurable: user)

      copilot_user.pr_summarizations_disabled!

      assert config.reload.pr_summarizations_disabled?
    end
  end

  context "#private_docs_enabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_private_docs_disabled, configurable: user)

      copilot_user.private_docs_enabled!

      assert config.reload.private_docs_enabled?
    end
  end

  context "#private_docs_disabled?" do
    context "when part of a disabled organization" do
      test "is true" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).private_docs_disabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_private_docs_enabled, configurable: user)

        assert copilot_user.private_docs_disabled?
      end
    end

    context "when part of org that enables it" do
      test "is false" do
        org = create(:organization)
        user = create(:user)
        org.add_member(user)
        Copilot::Organization.new(org).private_docs_enabled!
        create(:copilot_seat, organization: org, assigned_user: user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, :copilot_private_docs_disabled, configurable: user)

        refute copilot_user.private_docs_disabled?
      end
    end
  end

  context "private_docs_disabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_private_docs_enabled, configurable: user)

      copilot_user.private_docs_disabled!

      assert config.reload.private_docs_disabled?
    end
  end

  context "private_docs_enabled!" do
    test "updates each dotcom feature in the user's config" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)
      config = create(:copilot_configuration, :user, :copilot_private_docs_disabled, configurable: user)

      copilot_user.private_docs_enabled!

      assert config.reload.private_docs_enabled?
    end
  end

  context "copilot_plan" do
    test "for Copilot Individual plan users, returns individual" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      assert_equal copilot_user.copilot_plan, "individual"
    end

    test "for users with standalone orgs, returns business if no org has an enterprise plan" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)

      assert_equal copilot_user.copilot_plan, "business"
    end

    test "for users with enterprise-owned orgs, returns business if no org has an enterprise plan" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, business: business)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)

      assert_equal copilot_user.copilot_plan, "business"
    end

    test "for users with enterprise-owned orgs, returns enterprise if the business has an enterprise plan" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, business: business)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)
      copilot_user = Copilot::User.new(user)
      Copilot::Business.new(business).copilot_plan_enterprise!

      assert_equal copilot_user.copilot_plan, "enterprise"
    end
  end

  context "fine tuning organization" do
    test "empty when the user has no orgs" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      refute copilot_user.fine_tuning_organization
    end

    test "returns no org unless all orgs have private telemetry enabled" do
      user = create(:user)

      org1 = create(:business_organization)
      org1.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)

      org2 = create(:business_organization)
      org2.add_member user
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).private_telemetry_enabled!
      assert_nil Copilot::User.new(user).fine_tuning_organization
      Copilot::Organization.new(org1).private_telemetry_enabled!
      assert_equal org1,
        T.must(Copilot::User.new(user).fine_tuning_organization).organization_object
    end

    test "if multiple orgs have private telemetry enabled, and there is a custom model in use, returns the org for the first custom model" do
      user = create(:user)
      org1 = create(:business_organization)
      org1.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      Copilot::Organization.new(org1).private_telemetry_enabled!

      org2 = create(:business_organization)
      org2.add_member user
      create(:copilot_seat, organization: org2, assigned_user: user)
      Copilot::Organization.new(org2).private_telemetry_enabled!
      Orca::Model.create(
        organization: org2,
        pipeline_id: "test-model",
        resource: "test-resource",
        deployment: "test-deployment",
      )

      assert_equal org2,
        T.must(Copilot::User.new(user).fine_tuning_organization).organization_object
    end

    test "empty if no orgs have private telemetry enabled" do
      user = create(:user)
      org = create(:business_organization)
      org.add_member user
      create(:copilot_seat, organization: org, assigned_user: user)
      refute Copilot::User.new(user).fine_tuning_organization
    end
  end

  context "retrieval organization" do
    test "empty when the user has no orgs" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      refute copilot_user.rag_organization
    end

    test "returns the org if any org is on the copilot_retrieval_alpha_org feature flag" do
      user = create(:user)
      business = create(:business)
      retrieval_org = create(:organization, business: business)
      retrieval_org.enable_feature(:copilot_retrieval_alpha_org)
      retrieval_org.add_member(user)
      assert_equal Copilot::User.new(user).rag_organization, retrieval_org
    end

    test "empty if no orgs are on the copilot_retrieval_alpha_org feature flag" do
      user = create(:user)
      business = create(:business)
      org = create(:organization, business: business)
      org.add_member(user)
      refute Copilot::User.new(user).rag_organization
    end
  end

  context "telemetry" do
    test "user defaults to telemetry enabled" do
      user = create(:user)
      copilot_user = Copilot::User.new(user)

      configuration = create(:copilot_configuration, configurable: user)

      assert copilot_user.telemetry_enabled?
      assert configuration.user_telemetry_enabled?
    end

    test "disabling telemetry" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)
      copilot_user = Copilot::User.new(user)

      configuration = create(:copilot_configuration, configurable: user)

      assert copilot_user.telemetry_enabled?

      copilot_user.disable_telemetry!

      refute copilot_user.telemetry_enabled?
      refute configuration.reload.user_telemetry_enabled?

      assert_equal 1,
        GitHub.dogstats.increments("copilot.settings.telemetry_disabled").length
    end

    test "enabling telemetry" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      user = create(:user)
      copilot_user = Copilot::User.new(user)

      configuration = create(
        :copilot_configuration,
        configurable: user,
        user_telemetry: :disabled,
      )

      refute copilot_user.telemetry_enabled?
      refute configuration.reload.user_telemetry_enabled?

      copilot_user.enable_telemetry!

      assert copilot_user.telemetry_enabled?
      assert configuration.reload.user_telemetry_enabled?

      assert_equal 1,
        GitHub.dogstats.increments("copilot.settings.telemetry_enabled").length
    end

    test "Copilot for Business users have telemetry disabled" do
      user = create(:user)
      business = create(:business)
      organization = create(:organization, business: business)
      organization.add_member(user)

      create(
        :copilot_configuration,
        :user,
        configurable: user,
      )

      assert Copilot::User.new(user).telemetry_enabled?

      Copilot::Business.new(business).enable_copilot_for_all_organizations!

      assert Copilot::User.new(user).telemetry_enabled?

      create(:copilot_seat, organization: organization, assigned_user: user)

      refute Copilot::User.new(user).telemetry_enabled?
    end

    test "Copilot for Business users have telemetry enabled for special orgs" do
      user = create(:user)
      business = create(:business)
      organization = create(:organization, business: business)
      organization.add_member(user)

      create(
        :copilot_configuration,
        :user,
        configurable: user,
      )

      assert Copilot::User.new(user).telemetry_enabled?

      Copilot::Business.new(business).enable_copilot_for_all_organizations!

      assert Copilot::User.new(user).telemetry_enabled?

      create(:copilot_seat, organization: organization, assigned_user: user)

      Copilot::COPILOT_TELEMETRY_ORG_IDS.each do |org_id|
        ::User.any_instance.stubs(:organization_ids).returns([organization.id, org_id])
        assert Copilot::User.new(user).telemetry_enabled?
      end

      ::User.any_instance.stubs(:organization_ids).returns([organization.id])
      refute  Copilot::User.new(user).telemetry_enabled?
    end

    test "Proxima stamps have telemetry disabled" do
      on_multi_tenant_enterprise do
        user = create(:user)
        refute Copilot::User.new(user).telemetry_enabled?
      end
    end
  end

  context "#copilot_extensions_unconfigured?" do
    context "when the user belongs to an organization that is configured" do
      test "returns false" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).copilot_extensions_enabled!

        refute Copilot::User.new(user).copilot_extensions_unconfigured?
      end
    end

    context "when the user belongs to no configured organizations" do
      test "returns true" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)

        assert Copilot::User.new(user).copilot_extensions_unconfigured?
      end
    end
  end

  context "#copilot_extensions_configured?" do
    context "when the user belongs to an organization that is configured" do
      test "returns true" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)
        Copilot::Organization.new(org).copilot_extensions_enabled!

        assert Copilot::User.new(user).copilot_extensions_configured?
      end
    end

    context "when the user belongs to no configured organizations" do
      test "returns false" do
        user = create(:user)
        org = create(:business_organization)
        org.add_member user
        create(:copilot_seat, organization: org, assigned_user: user)

        refute Copilot::User.new(user).copilot_extensions_configured?
      end
    end
  end

  context "#copilot_extensions_enabled?" do
    test "true if the copilot_extensibility_policy_override flag is enabled for the user" do
      user = create(:user)
      GitHub.flipper[:copilot_extensibility_policy_override].enable(user)

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_enabled?
      assert_equal "enabled", copilot_user.copilot_extensions_setting
    end

    test "false if at least one business disables it" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      refute copilot_user.copilot_extensions_enabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end

    test "true if at least one business enables it and no others disable it" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_no_policy!

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_enabled?
      assert_equal "enabled", copilot_user.copilot_extensions_setting
    end

    test "true if not controlled by a business and at least one organization enables it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_enabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_enabled?
      assert_equal "enabled", copilot_user.copilot_extensions_setting
    end

    test "false if not controlled by a business and all organizations disable it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_disabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      refute copilot_user.copilot_extensions_enabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end

    test "true for cfi users in the copilot_extension_access flag" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      assert Copilot::User.new(user).has_cfi_access?
      GitHub.flipper[:copilot_extension_access].enable(user)

      assert Copilot::User.new(user).copilot_extensions_enabled?
      assert_equal "enabled", Copilot::User.new(user).copilot_extensions_setting
    end

    test "false for cfi users not in the copilot_extension_access flag" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      assert Copilot::User.new(user).has_cfi_access?
      GitHub.flipper[:copilot_extension_access].disable(user)

      refute Copilot::User.new(user).copilot_extensions_enabled?
      assert_equal "disabled", Copilot::User.new(user).copilot_extensions_setting
    end

    test "false by default" do
      user = create(:user)

      copilot_user = Copilot::User.new(user)
      refute copilot_user.copilot_extensions_enabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end
  end

  context "#copilot_extensions_disabled?" do
    test "false if the copilot_extensibility_policy_override flag is enabled for the user" do
      user = create(:user)
      GitHub.flipper[:copilot_extensibility_policy_override].enable(user)

      copilot_user = Copilot::User.new(user)
      refute copilot_user.copilot_extensions_disabled?
      assert_equal "enabled", copilot_user.copilot_extensions_setting
    end

    test "true if at least one business disables it" do
      user = create(:user)
      biz1 = create(:business)
      org1 = create(:organization, business: biz1)
      biz2 = create(:business)
      org2 = create(:organization, business: biz2)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Business.new(biz1).copilot_extensions_enabled!
      Copilot::Business.new(biz2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_disabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end

    test "false if not controlled by a business and at least one organization enables it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_enabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      refute copilot_user.copilot_extensions_disabled?
      assert_equal "enabled", copilot_user.copilot_extensions_setting
    end

    test "true if not controlled by a business and all organizations disable it" do
      user = create(:user)
      org1 = create(:organization)
      org2 = create(:organization)
      org1.add_member user
      org2.add_member user
      create(:copilot_seat, organization: org1, assigned_user: user)
      create(:copilot_seat, organization: org2, assigned_user: user)

      Copilot::Organization.new(org1).copilot_extensions_disabled!
      Copilot::Organization.new(org2).copilot_extensions_disabled!

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_disabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end

    test "true for cfi users not in the copilot_extension_access flag" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      assert Copilot::User.new(user).has_cfi_access?
      GitHub.flipper[:copilot_extension_access].disable(user)

      assert Copilot::User.new(user).copilot_extensions_disabled?
      assert_equal "disabled", Copilot::User.new(user).copilot_extensions_setting
    end

    test "false for cfi users in the copilot_extension_access flag" do
      user = create(:user)
      create(:copilot_free_user, user: user, subscribed: true)
      assert Copilot::User.new(user).has_cfi_access?
      GitHub.flipper[:copilot_extension_access].enable(user)

      refute Copilot::User.new(user).copilot_extensions_disabled?
      assert_equal "enabled", Copilot::User.new(user).copilot_extensions_setting
    end

    test "true by default" do
      user = create(:user)

      copilot_user = Copilot::User.new(user)
      assert copilot_user.copilot_extensions_disabled?
      assert_equal "disabled", copilot_user.copilot_extensions_setting
    end
  end

  context "#copilot_extensions_enabled!" do
    test "sets the config to enabled" do
      user = create(:user)
      user_config = create(:copilot_configuration, :user, configurable: user, copilot_extensions: :disabled)
      copilot_user = Copilot::User.new(user)

      copilot_user.copilot_extensions_enabled!

      assert user_config.reload.copilot_extensions_enabled?
    end
  end

  context "#copilot_extensions_disabled!" do
    test "sets the config to disabled" do
      user = create(:user)
      user_config = create(:copilot_configuration, :user, configurable: user, copilot_extensions: :enabled)
      copilot_user = Copilot::User.new(user)

      copilot_user.copilot_extensions_disabled!

      assert user_config.reload.copilot_extensions_disabled?
    end
  end
end if GitHub.copilot_enabled?

class CopilotUserSettingsStandalone < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @biz = create(:business, :default_managed, seats_plan_type: :basic)
    @user = create(:user)
    @enterprise_team = create(:enterprise_team, business: @biz)
  end

  setup do
    @biz.add_user_accounts([@user.id], business_roles_bitfield: 2)
    @biz.add_owner(@user, actor: @user)
    @enterprise_team.enterprise_team_memberships.create!(user_id: @user.id)
    @seat_assignment = Copilot::SeatAssignment.new(
      id: 1,
      owner_id: @biz.id,
      owner_type: "Business",
      assignable_type: "EnterpriseTeam",
      assignable_id: @enterprise_team.id,
      assigning_user: @user
    )
    @seat_assignment.save!
    @seat_assignment.convert_to_seats
  end

  context "IDE chat" do
    test "enabled if enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.chat_enabled?
      refute copilot_user.chat_disabled?
    end

    test "disabled if enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.chat_disabled?
      refute copilot_user.chat_enabled?
    end
  end

  context "cli" do
    test "enabled if enterprise owning enterprise team enables it" do
      Copilot::Business.new(@seat_assignment.owner).cli_enabled!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.cli_enabled?
      refute copilot_user.cli_disabled?
    end

    test "disabled if enterprise owning enterprise team disables it" do
      Copilot::Business.new(@seat_assignment.owner).cli_disabled!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.cli_disabled?
      refute copilot_user.cli_enabled?
    end
  end

  context "mobile chat" do
    test "enabled if enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_mobile_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.mobile_chat_enabled?
      refute copilot_user.mobile_chat_disabled?
    end

    test "disabled if enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_mobile_chat!
      copilot_user = Copilot::User.new(@user.reload)

      assert copilot_user.mobile_chat_disabled?
      refute copilot_user.mobile_chat_enabled?
    end

    test "plan is business" do
      assert_equal "business", Copilot::User.new(@user).copilot_plan
    end
  end
end if GitHub.copilot_enabled?

class CopilotUserSettingsStandaloneEMU < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
  end

  setup do
    @seat_assignment.convert_to_seats
  end

  context "IDE chat" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@seat_assignment.owner).enable_chat!

      user = @seat_assignment.seats.first.assigned_user
      copilot_user = Copilot::User.new(user)

      assert copilot_user.chat_enabled?
      refute copilot_user.chat_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@seat_assignment.owner).disable_chat!

      user = @seat_assignment.seats.first.assigned_user
      copilot_user = Copilot::User.new(user)

      assert copilot_user.chat_disabled?
      refute copilot_user.chat_enabled?
    end
  end

  context "cli" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@standalone_enterprise).cli_enabled!

      @user.reload

      assert Copilot::User.new(@user).cli_enabled?
      refute Copilot::User.new(@user).cli_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@standalone_enterprise).cli_disabled!

      @user.reload

      assert Copilot::User.new(@user).cli_disabled?
      refute Copilot::User.new(@user).cli_enabled?
    end
  end

  context "mobile chat" do
    test "enabled if owning enterprise for enterprise_team enables it" do
      Copilot::Business.new(@standalone_enterprise).enable_mobile_chat!

      @user.reload

      assert Copilot::User.new(@user).mobile_chat_enabled?
      refute Copilot::User.new(@user).mobile_chat_disabled?
    end

    test "disabled if owning enterprise for enterprise_team disables it" do
      Copilot::Business.new(@standalone_enterprise).disable_mobile_chat!

      @user.reload

      assert Copilot::User.new(@user).mobile_chat_disabled?
      refute Copilot::User.new(@user).mobile_chat_enabled?
    end
  end
end if TestEnv.test_with_all_emus? && GitHub.copilot_enabled?
