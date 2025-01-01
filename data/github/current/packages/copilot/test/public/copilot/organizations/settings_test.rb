# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotOrganizationsSettingsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    @mailer = T.let(mock, T.nilable(Mocha::Mock))
    T.must(@mailer).stubs(:deliver_later)
  end

  context "#telemetry_aggregation_enabled!" do
    test "enables for org if parent business is set to no_policy" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_no_policy!

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.telemetry_aggregation_enabled!

      assert copilot_org.telemetry_aggregation_enabled?
    end
  end

  context "#telemetry_aggregation_disabled!" do
    test "doesn't matter what the parent business does it can always be disabled" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_disabled!

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.telemetry_aggregation_disabled!

      refute copilot_org.telemetry_aggregation_enabled?
    end
  end

  context "#telemetry_aggregation_enabled?" do
    test "returns true if the parent business has it enabled" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_enabled!

      copilot_org = Copilot::Organization.new(organization)

      assert copilot_org.telemetry_aggregation_enabled?
    end

    test "returns false if the parent business has it disabled" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_disabled!

      copilot_org = Copilot::Organization.new(organization)

      refute copilot_org.telemetry_aggregation_enabled?
    end

    test "returns the organizations value if the parent business has no policy" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_no_policy!

      copilot_org = Copilot::Organization.new(organization)

      refute copilot_org.telemetry_aggregation_enabled?

      copilot_org.telemetry_aggregation_enabled!
      assert copilot_org.telemetry_aggregation_enabled?
    end
  end

  context "copilot_for_business_free?" do
    test "if the organization is in the flag" do
      organization = create(:organization)
      GitHub.flipper[:copilot_for_business_free].enable(organization)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.copilot_for_business_free?
    end

    test "if the business is in the flag" do
      organization = create(:copilot_for_business_enabled_free_organization)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.copilot_for_business_free?
    end

    test "nothing is in the flag" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      refute copilot_organization.copilot_for_business_free?
    end
  end

  context "copilot_for_business_enabled?" do
    test "allows feature flagged business" do
      organization = create(:copilot_for_business_enabled_organization)

      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.copilot_for_business_enabled?
    end

    test "allows standalone org with cfb enabled" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)
      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_organization.enable_copilot!(organization.admins.first)

      assert copilot_organization.copilot_for_business_enabled?
    end

    test "disallows standalone org with cfb  NOT enabled" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      refute copilot_organization.copilot_for_business_enabled?
    end
  end

  context "#configuration_defaults" do
    test "configuration defaults" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)
      copilot_organization.ensure_configuration!
      configuration = Copilot::Configuration.find_by!(configurable_id: organization.id, configurable_type: "Organization")

      assert_subset_hash({
        "copilot_enabled" => "disabled",
        "public_code_suggestions" => "blocked",
        "user_telemetry" => "disabled",
        "chat_enabled" => "unconfigured",
        "max_seats" => 0,
        "bing_github_chat" => "disabled",
        "user_feedback_opt_in" => "enabled",
      }, configuration.attributes)
    end

    test "inherits blocked setting from business" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.block_public_code_suggestions!
      organization = create(:organization, business: business)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.block_public_code_suggestions?
    end

    test "inherits allowed setting from business" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.allow_public_code_suggestions!
      organization = create(:organization, business: business)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.allow_public_code_suggestions?
    end

    test "no policy on business leaves org unchanged" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.no_public_code_suggestions_policy!
      organization = create(:organization, business: business)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.block_public_code_suggestions?
    end
  end

  context "#has_copilot_for_business?" do
    test "no business" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      refute copilot_organization.has_copilot_for_business?
    end

    test "no business, but copilot enabled" do
      organization = create(:copilot_for_business_enabled_non_enterprise_organization)
      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.has_copilot_for_business?
    end

    test "business disabled, no organizations enabled" do
      organization = create(:organization)
      business = create(:business)
      business.add_organization(organization)
      organization.reload

      copilot_business = Copilot::Business.new(business)
      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never
      copilot_business.disable_copilot!(business.owners.first)

      copilot_organization = Copilot::Organization.new(organization)
      refute copilot_organization.has_copilot_for_business?
    end

    test "business enabled for all organizations" do
      organization = create(:organization)
      business = create(:business)
      business.add_organization(organization)
      organization.reload

      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot_for_all_organizations!

      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.has_copilot_for_business?
    end

    test "business enabled for selected organizations, this org enabled" do
      organization = create(:organization)
      business = create(:business)
      business.add_organization(organization)
      organization.reload

      copilot_business = Copilot::Business.new(business)
      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_business.enable_copilot_for_selected_organizations!([
        organization.id
      ], business.owners.first)

      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.has_copilot_for_business?
    end

    test "business enabled for selected organizations, this org already disabled" do
      organization = create(:organization)
      other_organization = create(:organization)
      business = create(:business)
      business.add_organization(organization)
      business.add_organization(other_organization)
      organization.reload
      other_organization.reload

      copilot_business = Copilot::Business.new(business)

      # enable copilot for other org, leave original org disabled
      copilot_business.enable_copilot_for_selected_organizations!([
        other_organization.id
      ])

      copilot_organization = Copilot::Organization.new(organization)
      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never
      copilot_organization.disable_copilot!(organization.admins.first)

      refute copilot_organization.has_copilot_for_business?
    end
  end

  context "copilot enabled" do
    test "default value is disabled" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.copilot_disabled?
    end

    test "doesn't instrument if already disabled" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never
      copilot_organization.disable_copilot!(organization.admins.first)

      assert copilot_organization.copilot_disabled?
    end

    test "doesn't instrument if already enabled" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      configuration = create(
        :copilot_configuration, :organization, configurable: organization, chat_enabled: :disabled, public_code_suggestions: :allowed
      )
      configuration.enabled!

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never
      copilot_organization.enable_copilot!(organization.admins.first)

      assert copilot_organization.copilot_enabled?
    end

    test "enabling" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_organization.enable_copilot!(organization.admins.first)

      refute copilot_organization.copilot_disabled?
      assert copilot_organization.copilot_enabled?
    end

    test "disabling" do
      organization = create(:organization)
      copilot_organization = Copilot::Organization.new(organization)
      configuration = create(
        :copilot_configuration, :organization, configurable: organization, chat_enabled: :disabled, public_code_suggestions: :allowed
      )
      configuration.enabled!

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_organization.disable_copilot!(organization.admins.first)

      assert copilot_organization.copilot_disabled?
      refute copilot_organization.copilot_enabled?
    end

    test "enables the org if a business exists with CFB enabled for all orgs" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot_for_all_organizations!

      organization = create(:organization, business: business)
      copilot_organization = Copilot::Organization.new(organization)

      assert copilot_organization.copilot_enabled?
    end

    test "enables an org invited to a business with CFB enabled for all orgs" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.enable_copilot_for_all_organizations!

      organization = create(:organization)
      Copilot::Organization.new(organization).ensure_configuration!

      business.add_organization(organization)
      organization.reload

      copilot_organization = Copilot::Organization.new(organization)
      assert copilot_organization.copilot_enabled?
    end
  end

  context "chat enabled" do
    test "setting creates configuration record" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      assert_changes -> { Copilot::Configuration.count }, from: 0, to: 1 do
        copilot_org.enable_chat!
      end
    end

    test "defaults to chat unconfigured" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      refute copilot_org.chat_enabled?
      refute copilot_org.chat_disabled?
      refute copilot_org.chat_enabled_configured?
      assert_equal "unconfigured", copilot_org.chat_setting
    end

    test "enabling chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      refute copilot_org.chat_enabled_configured?
      assert configuration.chat_enabled_unconfigured?
      CopilotForBusinessMailer.expects(:chat_enabled_for_user).with(org, org.members.first).returns(@mailer).once

      copilot_org.enable_chat!

      assert configuration.reload.chat_enabled_enabled?

      assert copilot_org.chat_enabled_configured?
      assert copilot_org.chat_enabled?
      refute copilot_org.chat_disabled?
      assert_equal "enabled", copilot_org.chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.chat_enabled_enabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      refute copilot_org.chat_enabled_configured?
      assert configuration.chat_enabled_unconfigured?
      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, org.members.first).returns(@mailer).once

      copilot_org.disable_chat!

      assert configuration.reload.chat_enabled_disabled?

      assert copilot_org.chat_enabled_configured?
      assert copilot_org.chat_disabled?
      refute copilot_org.chat_enabled?
      assert_equal "disabled", copilot_org.chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.chat_enabled_disabled",
        tags: ["type:organization"],
      ).length
    end
  end

  context "mobile chat" do
    test "enabling mobile chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :disabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      CopilotMobileChatMailer.expects(:mobile_chat_enabled_for_user).with(org, org.members.first).returns(@mailer).once

      copilot_org.enable_mobile_chat!

      assert configuration.reload.mobile_chat_enabled?

      assert copilot_org.mobile_chat_enabled?
      refute copilot_org.mobile_chat_disabled?
      assert_equal "enabled", copilot_org.mobile_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.mobile_chat_enabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling mobile chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :enabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      CopilotMobileChatMailer.expects(:mobile_chat_disabled_for_user).with(org, org.members.first).returns(@mailer).once

      copilot_org.disable_mobile_chat!

      refute configuration.reload.mobile_chat_enabled?

      refute copilot_org.mobile_chat_enabled?
      assert copilot_org.mobile_chat_disabled?
      assert_equal "disabled", copilot_org.mobile_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.mobile_chat_disabled",
        tags: ["type:organization"],
      ).length
    end

    test "enabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.enable_mobile_chat!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.mobile_chat_policy_inherited?
      assert copilot_org.mobile_chat_enabled?
    end

    test "disabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.disable_mobile_chat!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.mobile_chat_policy_inherited?
      assert copilot_org.mobile_chat_disabled?
    end
  end

  context "a_chat" do
    test "enabling a_chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :disabled, a_chat: :disabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.a_chat_enabled!

      assert configuration.reload.a_chat_enabled?

      assert copilot_org.a_chat_enabled?
      refute copilot_org.a_chat_disabled?
      assert_equal "enabled", copilot_org.a_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.a_chat_enabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling a_chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :enabled, a_chat: :enabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.a_chat_disabled!

      refute configuration.reload.a_chat_enabled?

      refute copilot_org.a_chat_enabled?
      assert copilot_org.a_chat_disabled?
      assert_equal "disabled", copilot_org.a_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.a_chat_disabled",
        tags: ["type:organization"],
      ).length
    end

    test "enabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.a_chat_enabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.a_chat_policy_inherited?
      assert copilot_org.a_chat_enabled?
    end

    test "disabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.a_chat_disabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.a_chat_policy_inherited?
      assert copilot_org.a_chat_disabled?
    end
  end

  context "g_chat" do
    test "enabling g_chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :disabled, g_chat: :disabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.g_chat_enabled!

      assert configuration.reload.g_chat_enabled?

      assert copilot_org.g_chat_enabled?
      refute copilot_org.g_chat_disabled?
      assert_equal "enabled", copilot_org.g_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.g_chat_enabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling g_chat" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :enabled, g_chat: :enabled, public_code_suggestions: :unconfigured
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.g_chat_disabled!

      refute configuration.reload.g_chat_enabled?

      refute copilot_org.g_chat_enabled?
      assert copilot_org.g_chat_disabled?
      assert_equal "disabled", copilot_org.g_chat_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.g_chat_disabled",
        tags: ["type:organization"],
      ).length
    end

    test "enabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.g_chat_enabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.g_chat_policy_inherited?
      assert copilot_org.g_chat_enabled?
    end

    test "disabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.g_chat_disabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.g_chat_policy_inherited?
      assert copilot_org.g_chat_disabled?
    end
  end

  context "o1" do
    test "enabling o1" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :disabled, a_chat: :disabled, public_code_suggestions: :unconfigured, o1: :disabled,
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.o1_enabled!

      assert configuration.reload.o1_enabled?

      assert copilot_org.o1_enabled?
      refute copilot_org.o1_disabled?
      assert_equal "enabled", copilot_org.o1_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.o1_enabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling o1" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :unconfigured, mobile_chat: :enabled, a_chat: :enabled, public_code_suggestions: :unconfigured, o1: :enabled,
      )
      create(:copilot_seat, organization: org, assigned_user: org.members.first)

      copilot_org.o1_disabled!

      refute configuration.reload.o1_enabled?

      refute copilot_org.o1_enabled?
      assert copilot_org.o1_disabled?
      assert_equal "disabled", copilot_org.o1_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.o1_disabled",
        tags: ["type:organization"],
      ).length
    end

    test "enabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.o1_enabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.o1_policy_inherited?
      assert copilot_org.o1_enabled?
    end

    test "disabled policy is inherited from business" do
      org = create(:copilot_for_business_enabled_organization)
      biz = org.business

      copilot_biz = Copilot::Business.new(biz)

      copilot_biz.o1_disabled!

      copilot_org = Copilot::Organization.new(org)

      assert copilot_org.o1_policy_inherited?
      assert copilot_org.o1_disabled?
    end
  end

  context "public code suggestions" do
    test "setting creates configuration record" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      assert_changes -> { Copilot::Configuration.count }, from: 0, to: 1 do
        copilot_org.allow_public_code_suggestions!
      end
    end

    test "defaults to blocking public code suggestions" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      refute copilot_org.allow_public_code_suggestions?
      assert copilot_org.block_public_code_suggestions?
      assert copilot_org.public_code_suggestions_configured?
      assert_equal "enabled", copilot_org.snippy_setting
    end

    test "enabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :disabled, public_code_suggestions: :unconfigured
      )

      refute copilot_org.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_unconfigured?

      copilot_org.block_public_code_suggestions!

      assert configuration.reload.public_code_suggestions_blocked?

      assert copilot_org.public_code_suggestions_configured?
      assert copilot_org.block_public_code_suggestions?
      assert copilot_org.chat_disabled?
      refute copilot_org.allow_public_code_suggestions?
      assert_equal "enabled", copilot_org.snippy_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_blocked",
        tags: ["type:organization"],
      ).length
    end

    test "disabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :organization, configurable: org, chat_enabled: :disabled, public_code_suggestions: :unconfigured
      )

      refute copilot_org.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_unconfigured?

      copilot_org.allow_public_code_suggestions!

      assert configuration.reload.public_code_suggestions_allowed?

      assert copilot_org.public_code_suggestions_configured?
      refute copilot_org.block_public_code_suggestions?
      assert copilot_org.allow_public_code_suggestions?
      assert_equal "disabled", copilot_org.snippy_setting

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_allowed",
        tags: ["type:organization"],
      ).length
    end
  end

  context "#public_code_suggestions_sorting" do
    {
      "single" => [
        %i[blocked],
        %i[blocked],
      ],
      "blocked and allowed" => [
        %i[allowed blocked allowed],
        %i[blocked allowed allowed],
      ],
      "blocked and unconfigured" => [
        %i[unconfigured blocked unconfigured],
        %i[blocked unconfigured unconfigured],
      ],
    }.each do |name, (input, expected)|
      test name do
        copilot_orgs = []

        input.each do |setting|
          org = create(:organization)
          copilot_orgs << Copilot::Organization.new(org)
          create(
            :copilot_configuration,
            :organization,
            configurable: org,
            public_code_suggestions: setting,
            chat_enabled: :disabled
          )
        end

        assert_equal expected, copilot_orgs
          .sort_by(&:public_code_suggestions_sorting)
          .map { |org| org.send(:configuration).public_code_suggestions }
          .map(&:to_sym)
      end
    end

    test "stable sort through organization ID" do
      copilot_orgs = []

      10.times do
        org = create(:organization)
        copilot_orgs << Copilot::Organization.new(org)
        create(
          :copilot_configuration,
          :organization,
          configurable: org,
          public_code_suggestions: :allowed,
          chat_enabled: :disabled
        )
      end

      a = copilot_orgs.shuffle.sort_by(&:public_code_suggestions_sorting)
      b = copilot_orgs.shuffle.sort_by(&:public_code_suggestions_sorting)
      assert_equal a, b
    end
  end

  context "copilot_enablement_setting" do

    test "returns for a pending Copilot Business trial" do
      trial = create(:copilot_business_trial, :organization, state: :pending)
      copilot_org = Copilot::Organization.new(trial.trialable)
      assert_equal "Copilot Business Trial Pending", copilot_org.copilot_enablement_setting
    end

    test "returns for a pending Copilot Enterprise trial" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      trial = create(:copilot_business_trial, :organization,
        trialable: create(:organization, :enterprise_linked),
        state: :pending,
        copilot_plan: "enterprise",
      )
      copilot_org = Copilot::Organization.new(trial.trialable)
      assert_equal "Copilot Enterprise Trial Pending", copilot_org.copilot_enablement_setting
    end

    test "returns for a business enabled for all organizations" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(org)
      T.must(copilot_org.copilot_business).enable_copilot_for_all_organizations!
      assert_equal "Enabled By Enterprise Admin (All Orgs)", copilot_org.copilot_enablement_setting
    end

    test "returns for a business enabled for selected organizations (not this one)" do
      other_org = create(:copilot_for_business_enabled_organization)
      copilot_business = Copilot::Business.new(other_org.business.reload)

      assert copilot_business.copilot_enabled_for_all_organizations?

      Copilot::Business.new(other_org.business).enable_copilot_for_selected_organizations!([other_org.id], other_org.business.owners.first)

      copilot_business = Copilot::Business.new(other_org.business.reload)
      assert copilot_business.copilot_enabled_for_selected_organizations?

      copilot_org = Copilot::Organization.new(other_org)
      assert copilot_org.copilot_enabled?

      org = create(:enterprise_linked_organization, business: other_org.business)
      assert_equal other_org.business.id, org.business.id

      copilot_business = Copilot::Business.new(org.business.reload)
      assert copilot_business.copilot_enabled_for_selected_organizations?

      copilot_org = Copilot::Organization.new(org)
      refute copilot_org.copilot_enabled?

      assert_equal "Not Enabled for This Organization By Enterprise Admin", copilot_org.copilot_enablement_setting
    end

    test "returns for a business enabled for selected organizations (this one)" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_business = Copilot::Business.new(org.business.reload)

      assert copilot_business.copilot_enabled_for_all_organizations?
      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).never
      Copilot::Business.new(org.business).enable_copilot_for_selected_organizations!([org.id], org.business.owners.first)

      copilot_business = Copilot::Business.new(org.business.reload)
      assert copilot_business.copilot_enabled_for_selected_organizations?

      copilot_org = Copilot::Organization.new(org)
      assert copilot_org.copilot_enabled?

      assert_equal "Enabled By Enterprise Admin", copilot_org.copilot_enablement_setting
    end

    test "returns for a business enabled for all disabled" do
      org = create(:copilot_for_business_enabled_organization)
      copilot_business = Copilot::Business.new(org.business.reload)

      assert copilot_business.copilot_enabled_for_all_organizations?

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once

      Copilot::Business.new(org.business).disable_copilot!(org.business.admins.first)

      copilot_business = Copilot::Business.new(org.business.reload)
      assert copilot_business.copilot_disabled?

      copilot_org = Copilot::Organization.new(org)
      assert copilot_org.copilot_disabled?

      assert_equal "Disabled By Enterprise Admin", copilot_org.copilot_enablement_setting
    end

    test "returns for a standalone org that is disabled" do
      org = create(:credit_card_organization)

      copilot_org = Copilot::Organization.new(org)
      assert copilot_org.copilot_disabled?

      assert_equal "Not Enabled by Organization Admin", copilot_org.copilot_enablement_setting
    end

    test "returns for a standalone org that is enabled" do
      org = create(:credit_card_organization)

      copilot_org = Copilot::Organization.new(org)
      assert copilot_org.copilot_disabled?

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_org.enable_copilot!(org.admins.first)
      assert copilot_org.copilot_enabled?

      assert_equal "Enabled by Organization Admin", copilot_org.copilot_enablement_setting
    end
  end

  context "#cli_disabled!" do
    test "sets cli to disabled" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, cli: :enabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(@mailer).once

      copilot_org.cli_disabled!

      assert config.reload.cli_disabled?
    end

    test "does not send an email when send_email is false" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, cli: :enabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(@mailer).never

      copilot_org.cli_disabled!(false)

      assert config.reload.cli_disabled?
    end
  end

  context "#cli_enabled!" do
    test "sets cli to enabled" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, cli: :disabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotForBusinessMailer.expects(:cli_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).once

      copilot_org.cli_enabled!

      assert config.reload.cli_enabled?
    end

    test "does not send an email when send_email is false" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, cli: :enabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotForBusinessMailer.expects(:cli_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).never

      copilot_org.cli_enabled!(false)

      assert config.reload.cli_enabled?
    end
  end

  context "#cli_no_policy!" do
    test "does nothing since orgs cannot be no_policy" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)
      config = create(:copilot_configuration, :organization, cli: :enabled, configurable: org)

      copilot_org.cli_no_policy!

      refute config.reload.cli_no_policy?
      assert config.reload.cli_enabled?
    end
  end

  context "#copilot_for_dotcom_unconfigured!" do
    test "sets all copilot for dotcom features to unconfigured" do
      org = create(:organization)
      copilot_org = Copilot::Organization.new(org)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      copilot_org.copilot_for_dotcom_unconfigured!

      assert config.reload.dotcom_chat_unconfigured?
      assert config.reload.pr_summarizations_unconfigured?
    end
  end

  context "#copilot_for_dotcom_disabled!" do
    test "sets all copilot for dotcom features to disabled and sends an email when a user loses Copilot Enterprise access and the enterprise has the copilot_for_enterprise flag enabled" do
      business = create(:business)
      org = create(:organization, business: business)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)
      GitHub.flipper[:copilot_for_enterprise].enable(business)
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(@mailer).once

      copilot_org.copilot_for_dotcom_disabled!

      assert config.reload.dotcom_chat_disabled?
      assert config.reload.pr_summarizations_disabled?
    end

    test "does not send an email when send_email is false" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(@mailer).never

      copilot_org.copilot_for_dotcom_disabled!(false)

      assert config.reload.dotcom_chat_disabled?
      assert config.reload.pr_summarizations_disabled?
    end

    test "does not send an email for standalone orgs" do
      # enterprise-less orgs do not have this feature available in the UI,
      # but we should explicitly test it here
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(@mailer).never

      copilot_org.copilot_for_dotcom_disabled!(true)

      assert copilot_org.dotcom_chat_disabled?
      assert copilot_org.pr_summarizations_disabled?
    end

    test "sends email to org admins when an enterprise trial expires" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      org = create(:copilot_for_business_enabled_organization)
      trial = Copilot::BusinessTrial.new(
          managing_user: create(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: org,
          copilot_plan: "enterprise",
        )
      trial.expired!
      copilot_org = Copilot::Organization.new(org)

      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(@mailer).once
      copilot_org.copilot_for_dotcom_disabled!(true)
    end

    test "sends email to org admins based on org copilot plan when mixed licenses flag is active" do
      GitHub.flipper[:copilot_mixed_licenses].enable
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      org = create(:copilot_for_business_enabled_organization)
      Copilot::Business.new(org.business).copilot_plan_business!
      trial = Copilot::BusinessTrial.new(
          managing_user: create(:user),
          started_at: Date.current,
          ends_at: Date.current + 1.day,
          trial_length: 1,
          trialable: org,
          copilot_plan: "enterprise",
        )
      trial.expired!
      copilot_org = Copilot::Organization.new(org)
      copilot_org.copilot_plan_enterprise!

      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(@mailer).once
      copilot_org.copilot_for_dotcom_disabled!(true)
    end

    test "sends email to each seat holder based on org copilot plan when mixed licesnses flag is active" do
      GitHub.flipper[:copilot_mixed_licenses].enable

      org = create(:copilot_for_business_enabled_organization)
      user = create(:user)
      org.add_member(user)
      create(:copilot_seat, organization: org, assigned_user: user)

      Copilot::Business.new(org.business).copilot_plan_business!

      copilot_org = Copilot::Organization.new(org)
      copilot_org.copilot_plan_enterprise!

      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, user).returns(@mailer).once

      copilot_org.copilot_for_dotcom_disabled!(true)

      assert_equal copilot_org.copilot_plan, "enterprise"
    end
  end

  context "#copilot_for_dotcom_enabled!" do
    test "sets all copilot for dotcom features to enabled and sends an email when a user gets Copilot Enterprise access and the enterprise has the copilot_for_enterprise flag enabled" do
      business = create(:business)
      org = create(:organization, business: business)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)
      GitHub.flipper[:copilot_for_enterprise].enable(business)

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).once
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(@mailer).never

      copilot_org.copilot_for_dotcom_enabled!

      assert config.reload.dotcom_chat_enabled?
      assert config.reload.pr_summarizations_enabled?
    end

    test "sets all copilot for dotcom features to enabled and sends an email when a user gets Copilot Enterprise access and the enterprise has a copilot_enterprise plan" do
      business = create(:business)
      Copilot::Business.new(business).copilot_plan_enterprise!
      org = create(:organization, business: business)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(@mailer).once

      copilot_org.copilot_for_dotcom_enabled!

      assert config.reload.dotcom_chat_enabled?
      assert config.reload.pr_summarizations_enabled?
    end

    test "sets all copilot for dotcom features to enabled sends an email when a user gets Copilot Enterprise access via Copilot Enterprise trial" do
      business = create(:business)
      org = create(:organization, business: business)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)

      Copilot::BusinessTrial.create_trial!(org, org.admins.first, copilot_plan: "enterprise")

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, true).returns(@mailer).once

      copilot_org.copilot_for_dotcom_enabled!

      assert config.reload.dotcom_chat_enabled?
      assert config.reload.pr_summarizations_enabled?
    end

    test "starts a pending Copilot enterprise trial if one exists and there are Copilot seats" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      copilot_seat = create(:copilot_seat)
      org = copilot_seat.organization
      trial = create(:copilot_business_trial, :organization,
        copilot_plan: "enterprise",
        state: "pending",
        trialable: org,
      )

      assert trial.pending?

      copilot_org = Copilot::Organization.new(org)
      copilot_org.copilot_for_dotcom_enabled!

      assert trial.reload.recently_started?
    end

    test "does not start a pending Copilot enterprise trial if one exists but there are no Copilot seats" do
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      org = create(:organization, :enterprise_linked)
      trial = create(:copilot_business_trial, :organization,
        copilot_plan: "enterprise",
        state: "pending",
        trialable: org,
      )

      assert trial.pending?

      copilot_org = Copilot::Organization.new(org)
      copilot_org.copilot_for_dotcom_enabled!

      assert trial.reload.pending?
    end

    test "does not send an email when send_email is false" do
      org = create(:organization)
      user = create(:user)
      org.add_member(user)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      seat = create(:copilot_seat, organization: org, assigned_user: user)
      copilot_org = Copilot::Organization.new(org)

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(@mailer).never

      copilot_org.copilot_for_dotcom_enabled!(false)

      assert config.reload.dotcom_chat_enabled?
      assert config.reload.pr_summarizations_enabled?
    end
  end

  context "#copilot_for_dotcom_no_policy!" do
    test "does nothing since orgs cannot be no_policy without mixed license support" do
      org = create(:organization)
      org.disable_feature(:copilot_mixed_licenses)
      copilot_org = Copilot::Organization.new(org)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      copilot_org.copilot_for_dotcom_no_policy!

      refute config.reload.dotcom_chat_no_policy?
      assert config.reload.dotcom_chat_enabled?
      refute config.reload.pr_summarizations_no_policy?
      assert config.reload.pr_summarizations_enabled?
    end

    test "disabled enterprise features when the copilot_mixed_licenses feature flag is active" do
      org = create(:organization)
      org.enable_feature(:copilot_mixed_licenses)
      copilot_org = Copilot::Organization.new(org)
      config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)

      copilot_org.copilot_for_dotcom_no_policy!

      config.reload

      assert config.dotcom_chat_no_policy?
      assert config.pr_summarizations_no_policy?
      assert config.github_enterprise_feature_group_no_policy?
    end
  end

  context "#bing_github_chat_disabled?" do
    test "defaults to disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))

      assert copilot_org.bing_github_chat_disabled?
    end

    test "returns true if Bing is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_disable!

      assert copilot_org.bing_github_chat_disabled?
    end

    test "returns false if Bing is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_enable!

      refute copilot_org.bing_github_chat_disabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.bing_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.bing_github_chat_disabled?
    end
  end

  context "#bing_github_chat_enabled?" do
    test "returns true if Bing is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_enable!

      assert copilot_org.bing_github_chat_enabled?
    end

    test "returns false if Bing is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_disable!

      refute copilot_org.bing_github_chat_enabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.bing_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      assert copilot_org.bing_github_chat_enabled?
    end
  end

  context "#bing_github_chat_inherited?" do
    test "returns false if there is no business" do
      copilot_org = Copilot::Organization.new(create(:organization))

      refute copilot_org.bing_github_chat_policy_inherited?
    end
  end

  context "#bing_github_chat_disable!" do
    test "can disable Bing for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_disable!

      assert copilot_org.bing_github_chat_disabled?
    end

    test "acts as no-op if the business has a Bing policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.bing_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.bing_github_chat_disabled?

      copilot_org.bing_github_chat_disable!

      refute copilot_org.bing_github_chat_disabled?
    end
  end

  context "#bing_github_chat_enable!" do
    test "can enable Bing for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.bing_github_chat_enable!

      assert copilot_org.bing_github_chat_enabled?
    end

    test "acts as no-op if the business has a Bing policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.bing_github_chat_disable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.bing_github_chat_enabled?

      copilot_org.bing_github_chat_enable!

      refute copilot_org.bing_github_chat_enabled?
    end
  end

  context "#beta_features_github_chat_disabled?" do
    test "defaults to disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))

      assert copilot_org.beta_features_github_chat_disabled?
    end

    test "returns true if beta features is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_disable!

      assert copilot_org.beta_features_github_chat_disabled?
    end

    test "returns false if beta features is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_enable!

      refute copilot_org.beta_features_github_chat_disabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.beta_features_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.beta_features_github_chat_disabled?
    end
  end

  context "#beta_features_github_chat_enabled?" do
    test "returns true if beta features is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_enable!

      assert copilot_org.beta_features_github_chat_enabled?
    end

    test "returns false if beta features is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_disable!

      refute copilot_org.beta_features_github_chat_enabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.beta_features_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      assert copilot_org.beta_features_github_chat_enabled?
    end
  end

  context "#beta_features_github_chat_inherited?" do
    test "returns false if there is no business" do
      copilot_org = Copilot::Organization.new(create(:organization))

      refute copilot_org.beta_features_github_chat_policy_inherited?
    end
  end

  context "#beta_features_github_chat_disable!" do
    test "can disable beta features for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_disable!

      assert copilot_org.beta_features_github_chat_disabled?
    end

    test "acts as no-op if the business has a beta features policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.beta_features_github_chat_enable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.beta_features_github_chat_disabled?

      copilot_org.beta_features_github_chat_disable!

      refute copilot_org.beta_features_github_chat_disabled?
    end
  end

  context "#beta_features_github_chat_enable!" do
    test "can enable beta features for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.beta_features_github_chat_enable!

      assert copilot_org.beta_features_github_chat_enabled?
    end

    test "acts as no-op if the business has a beta features policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.beta_features_github_chat_disable!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.beta_features_github_chat_enabled?

      copilot_org.beta_features_github_chat_enable!

      refute copilot_org.beta_features_github_chat_enabled?
    end
  end

  context "#user_feedback_opt_in_disabled?" do
    test "defaults to enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))

      assert copilot_org.user_feedback_opt_in_enabled?
    end

    test "returns true if Bing is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.disable_user_feedback!

      assert copilot_org.user_feedback_opt_in_disabled?
    end

    test "returns false if Bing is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.enable_user_feedback!

      refute copilot_org.user_feedback_opt_in_disabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.enable_user_feedback!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.user_feedback_opt_in_disabled?
    end
  end

  context "#user_feedback_opt_in_enabled?" do
    test "returns true if Bing is enabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.enable_user_feedback!

      assert copilot_org.user_feedback_opt_in_enabled?
    end

    test "returns false if Bing is disabled" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.disable_user_feedback!

      refute copilot_org.user_feedback_opt_in_enabled?
    end

    test "inherits from business" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.enable_user_feedback!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      assert copilot_org.user_feedback_opt_in_enabled?
    end
  end

  context "#user_feedback_opt_in_inherited?" do
    test "returns false if there is no business" do
      copilot_org = Copilot::Organization.new(create(:organization))

      refute copilot_org.user_feedback_opt_in_policy_inherited?
    end

    test "returns false if the business does not have a dotcom chat policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_no_policy!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.user_feedback_opt_in_policy_inherited?
    end

    test "returns true if the business has a dotcom chat enabled policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      assert copilot_org.user_feedback_opt_in_policy_inherited?
    end

    test "returns true if the business has a dotcom chat disabled policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_disabled!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      assert copilot_org.user_feedback_opt_in_policy_inherited?
    end
  end

  context "#disable_user_feedback!" do
    test "can disable Bing for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.disable_user_feedback!

      assert copilot_org.user_feedback_opt_in_disabled?
    end

    test "acts as no-op if the business has a Bing policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.enable_user_feedback!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.user_feedback_opt_in_disabled?

      copilot_org.disable_user_feedback!

      refute copilot_org.user_feedback_opt_in_disabled?
    end
  end

  context "#enable_user_feedback!" do
    test "can enable user feedback for the org" do
      copilot_org = Copilot::Organization.new(create(:business_organization))
      copilot_org.enable_user_feedback!

      assert copilot_org.user_feedback_opt_in_enabled?
    end

    test "acts as no-op if the business has a user feedback policy" do
      biz = create(:business)
      copilot_biz = Copilot::Business.new(biz)
      copilot_biz.copilot_for_dotcom_enabled!
      copilot_biz.disable_user_feedback!

      copilot_org = Copilot::Organization.new(create(:business_organization, business: biz))

      refute copilot_org.user_feedback_opt_in_enabled?

      copilot_org.enable_user_feedback!

      refute copilot_org.user_feedback_opt_in_enabled?
    end
  end

  context "copilot_plan" do
    test "for non-enterprise-owned orgs, returns business" do
      org = create(:organization)

      assert_equal Copilot::Organization.new(org).copilot_plan, "business"
    end

    context "for enterprise-owner orgs" do
      test "returns the plan of the owning enterprise when mixed licenses flag is disabled" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_organization = Copilot::Organization.new(organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_business.copilot_plan_enterprise!
        # Note that this isnt actually possible to toggle in the interface with the feature flag disabled / in production
        # but I want to make sure it is not logically possible.
        copilot_organization.copilot_plan_business!

        assert_equal Copilot::Organization.new(organization).copilot_plan, "enterprise"
      end

      test "returns the plan of the organization when mixed licenses flag is enabled" do
        GitHub.flipper[:copilot_mixed_licenses].enable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_business.copilot_plan_enterprise!

        assert_equal Copilot::Organization.new(organization).copilot_plan, "business"
      end

      test "return `enterprise` if org plan is enterprise when mixed licenses flag is enabled" do
        GitHub.flipper[:copilot_mixed_licenses].enable

        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)
        copilot_org.copilot_plan_enterprise!

        assert_equal copilot_org.copilot_plan, "enterprise"
        assert_equal copilot_business.copilot_plan, "business"
      end

      test "sends an email to admin and users when the org's copilot plan is upgraded" do
        GitHub.flipper[:copilot_mixed_licenses].enable

        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        seat = create(:copilot_seat, organization: organization)
        mailer = mock
        mailer.stubs(:deliver_later)

        CopilotEnterpriseMailer.expects(:welcome_org_admins).with(organization).returns(mailer).once
        CopilotEnterpriseMailer.expects(:welcome_individual).with(organization, seat.assigned_user).returns(mailer).once
        copilot_org.copilot_plan_enterprise!
      end

      test "return `business` if the org plan is business or undefined when mixed licenses flag is enabled" do
        GitHub.flipper[:copilot_mixed_licenses].enable

        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_business.copilot_plan_business!

        assert_equal copilot_org.copilot_plan, "business"
        assert copilot_org.copilot_plan_unconfigured?

        copilot_org.copilot_plan_business!


        assert_equal copilot_org.copilot_plan, "business"
        refute copilot_org.copilot_plan_unconfigured?
      end

      test "sends an email to admin and users when the org's copilot plan is downgraded" do
        GitHub.flipper[:copilot_mixed_licenses].enable

        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        seat = create(:copilot_seat, organization: organization)
        copilot_org.copilot_plan_enterprise!
        mailer = mock
        mailer.stubs(:deliver_later)

        CopilotForBusinessMailer.expects(:welcome_org_admins).with(organization).returns(mailer).once
        CopilotForBusinessMailer.expects(:welcome_individual).with(organization, seat.assigned_user).returns(mailer).once
        copilot_org.copilot_plan_business!
      end

      test "return enterprise if only org is enterprise and not another org in the same enterprise" do
        GitHub.flipper[:copilot_mixed_licenses].enable

        organization = create(:copilot_for_business_enabled_organization)
        organization2 = create(:copilot_for_business_enabled_organization, business: organization.business)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)
        copilot_org.copilot_plan_enterprise!

        assert_equal copilot_org.copilot_plan, "enterprise"
        assert_equal Copilot::Organization.new(organization2).copilot_plan, "business"
        assert_equal copilot_business.copilot_plan, "business"
      end
    end
  end

  context "#copilot_plan" do
    context "with copilot_mixed_licenses enabled" do
      test "returns the correct plan when from_config is true" do
        GitHub.flipper[:copilot_mixed_licenses].enable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        assert_equal "unconfigured", copilot_org.copilot_plan(from_config: true)
      end

      test "returns business when org has unconfigured plan" do
        GitHub.flipper[:copilot_mixed_licenses].enable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        assert_equal "business", copilot_org.copilot_plan
      end

      test "returns the underlying plan from the config when org has a plan" do
        GitHub.flipper[:copilot_mixed_licenses].enable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        copilot_org.copilot_plan_enterprise!

        assert_equal "enterprise", copilot_org.copilot_plan
      end
    end

    context "with copilot_mixed_licenses disabled" do
      test "returns the correct plan when from config is true" do
        GitHub.flipper[:copilot_mixed_licenses].disable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        copilot_biz = Copilot::Business.new(organization.business)
        copilot_biz.copilot_plan_enterprise!

        assert_equal "enterprise", copilot_org.copilot_plan(from_config: true)
      end


      test "returns enterprise-level plan when org has a business" do
        GitHub.flipper[:copilot_mixed_licenses].disable
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)
        copilot_biz = Copilot::Business.new(organization.business)

        assert_equal copilot_biz.copilot_plan, copilot_org.copilot_plan
      end

      test "returns business for standalone orgs" do
        GitHub.flipper[:copilot_mixed_licenses].disable
        organization = create(:copilot_for_business_enabled_non_enterprise_organization)
        copilot_org = Copilot::Organization.new(organization)

        assert_equal "business", copilot_org.copilot_plan
      end
    end
  end

  context "#copilot_plan_enterprise!" do
    test "plan cannot be set if mixed licenses are not enabled" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.copilot_plan_enterprise!

      assert_equal "business", copilot_org.copilot_plan
      refute copilot_org.has_configured_copilot_plan?
    end

    test "plan cannot be set if the org has an active trial" do
      organization = create(:copilot_for_business_enabled_organization)
      create(:copilot_business_trial, :final_day, :organization, trialable: organization)

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.copilot_plan_enterprise!

      assert_equal "business", copilot_org.copilot_plan
      refute copilot_org.has_configured_copilot_plan?
    end
  end

  context "#copilot_plan_business!" do
    test "plan cannot be set if mixed licenses are not enabled" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.copilot_plan_business!

      assert_equal "business", copilot_org.copilot_plan
      refute copilot_org.has_configured_copilot_plan?
    end

    test "plan cannot be set if the org has an active trial" do
      organization = create(:copilot_for_business_enabled_organization)
      create(:copilot_business_trial, :final_day, :organization, trialable: organization)

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.copilot_plan_business!

      assert_equal "business", copilot_org.copilot_plan
      refute copilot_org.has_configured_copilot_plan?
    end
  end

  context "#private_docs" do
    context "no_policy" do
      test "does nothing since orgs cannot be no_policy" do
        org = create(:organization)
        copilot_org = Copilot::Organization.new(org)
        config = create(:copilot_configuration, :organization, :copilot_private_docs_enabled, configurable: org)

        copilot_org.private_docs_no_policy!

        refute config.reload.private_docs_no_policy?
        assert config.reload.private_docs_enabled?
        refute config.reload.private_docs_no_policy?
        assert config.reload.private_docs_enabled?
      end
    end

    context "disabled!" do
      test "sets private docs to disabled" do
        org = create(:organization)
        copilot_org = Copilot::Organization.new(org)
        config = create(:copilot_configuration, :organization, :copilot_private_docs_enabled, configurable: org)

        copilot_org.private_docs_disabled!

        assert config.reload.private_docs_disabled?
      end
    end

    context "#enabled!" do
      test "sets private docs to enabled" do
        org = create(:organization)
        copilot_org = Copilot::Organization.new(org)
        config = create(:copilot_configuration, :organization, :copilot_private_docs_disabled, configurable: org)

        copilot_org.private_docs_enabled!

        assert config.reload.private_docs_enabled?
      end
    end
  end

  context "#copilot_extensions_enabled!" do
    test "enables copilot extensions for the organization" do
      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org, copilot_extensions: :disabled)
      copilot_org = Copilot::Organization.new(org)

      copilot_org.copilot_extensions_enabled!

      assert copilot_org.copilot_extensions_enabled?
      assert org_config.reload.copilot_extensions_enabled?
    end
  end

  context "#copilot_extensions_disabled!" do
    test "disables copilot extensions for the business and its organizations" do
      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org, copilot_extensions: :enabled)
      copilot_org = Copilot::Organization.new(org)

      copilot_org.copilot_extensions_disabled!

      assert copilot_org.copilot_extensions_disabled?
      assert org_config.reload.copilot_extensions_disabled?
    end
  end

  context "#private_telemetry_enabled!" do
    test "enables private telemetry for the organization" do
      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org, private_telemetry: :disabled)
      copilot_org = Copilot::Organization.new(org)

      copilot_org.private_telemetry_enabled!

      assert copilot_org.private_telemetry_enabled?
      assert org_config.reload.private_telemetry_enabled?
    end
  end

  context "#private_telemetry_disabled!" do
    test "disables copilot extensions for the business and its organizations" do
      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org, private_telemetry: :enabled)
      copilot_org = Copilot::Organization.new(org)

      copilot_org.private_telemetry_disabled!

      assert copilot_org.private_telemetry_disabled?
      assert org_config.reload.private_telemetry_disabled?
    end
  end

  context "#cancel_copilot_plan_downgrade!" do
    test "does nothing without the copilot_mixed_licenses feature flag" do
      GitHub.flipper[:copilot_mixed_licenses].disable

      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org)
      copilot_org = Copilot::Organization.new(org)
      org_config.update(pending_plan_downgrade_date: 2.days.from_now)

      copilot_org.cancel_copilot_plan_downgrade!

      org_config.reload

      refute_nil org_config.pending_plan_downgrade_date
    end

    test "unsets the scheduled downgrade date" do
      org = create(:organization)
      org.enable_feature(:copilot_mixed_licenses)
      org_config = create(:copilot_configuration, :organization, configurable: org)
      copilot_org = Copilot::Organization.new(org)
      org_config.update(pending_plan_downgrade_date: 2.days.from_now)

      copilot_org.cancel_copilot_plan_downgrade!

      org_config.reload

      assert_nil org_config.pending_plan_downgrade_date
    end
  end

  context "#copilot_plan_downgrade!" do
    test "does nothing without the copilot_mixed_licenses feature flag" do
      GitHub.flipper[:copilot_mixed_licenses].disable

      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org)
      copilot_org = Copilot::Organization.new(org)
      org_config.update(pending_plan_downgrade_date: 2.days.from_now)

      copilot_org.copilot_plan_downgrade!

      org_config.reload

      refute_nil org_config.pending_plan_downgrade_date
      assert org_config.copilot_plan_unconfigured?
      assert org_config.dotcom_chat_unconfigured?
      assert org_config.pr_summarizations_unconfigured?
      assert org_config.github_enterprise_feature_group_unconfigured?
    end

    test "does not unset copilot in dotcom features" do
      org = create(:organization)
      org.enable_feature(:copilot_mixed_licenses)
      org_config = create(
        :copilot_configuration,
        :organization,
        configurable: org,
        copilot_plan: :enterprise,
        dotcom_chat: :enabled,
        pr_summarizations: :enabled,
        github_enterprise_feature_group: :enabled
      )
      copilot_org = Copilot::Organization.new(org)
      org_config.update(pending_plan_downgrade_date: 2.days.from_now)

      copilot_org.copilot_plan_downgrade!

      org_config.reload

      assert org_config.copilot_plan_business?
      assert_nil org_config.pending_plan_downgrade_date
      refute org_config.dotcom_chat_no_policy?
      refute org_config.pr_summarizations_no_policy?
      refute org_config.github_enterprise_feature_group_no_policy?
    end
  end

  context "#schedule_copilot_plan_downgrade!" do
    test "does nothing if the copilot_mixed_licenses flag is not enabled" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      org = create(:organization)
      org_config = create(:copilot_configuration, :organization, configurable: org)

      ::Copilot::Instrumenter.expects(:instrument_copilot_plan_downgrade_scheduled).never
      Copilot::Organization.new(org).schedule_copilot_plan_downgrade!

      org_config.reload

      assert_nil org_config.pending_plan_downgrade_date
      assert_equal 0, GitHub.dogstats.increments(
        "copilot.settings.schedule_copilot_plan_downgrade",
      ).length
    end

    test "does nothing if copilot plan is not enterprise" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      org = create(:organization)
      org.enable_feature(:copilot_mixed_licenses)
      org_config = create(:copilot_configuration, :organization, configurable: org, copilot_plan: :business)

      ::Copilot::Instrumenter.expects(:instrument_copilot_plan_downgrade_scheduled).never
      Copilot::Organization.new(org).schedule_copilot_plan_downgrade!

      org_config.reload

      assert_nil org_config.pending_plan_downgrade_date
      assert_equal 0, GitHub.dogstats.increments(
        "copilot.settings.schedule_copilot_plan_downgrade",
      ).length
    end

    test "does nothing if the org doesn't have a parent business" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      org = create(:organization)
      org.enable_feature(:copilot_mixed_licenses)
      org_config = create(:copilot_configuration, :organization, configurable: org, copilot_plan: :enterprise)

      ::Copilot::Instrumenter.expects(:instrument_copilot_plan_downgrade_scheduled).never
      Copilot::Organization.new(org).schedule_copilot_plan_downgrade!

      org_config.reload

      assert_nil org_config.pending_plan_downgrade_date
      assert_equal 0, GitHub.dogstats.increments(
        "copilot.settings.schedule_copilot_plan_downgrade",
      ).length
    end

    test "sets the scheduled downgrade date to the parent businesses next billing cycle start date" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      organization = create(:copilot_for_business_enabled_organization)
      organization.enable_feature(:copilot_mixed_licenses)
      business = organization.business

      copilot_org = Copilot::Organization.new(organization)
      copilot_config = Copilot::Configuration
        .where(configurable_id: organization.id, configurable_type: "Organization")
        .first!
      copilot_config.update(copilot_plan: :enterprise)

      ::Copilot::Instrumenter.expects(:instrument_copilot_plan_downgrade_scheduled).once
      copilot_org.schedule_copilot_plan_downgrade!

      assert_equal(
        business.next_metered_billing_cycle_starts_at.to_date,
        copilot_config.reload.pending_plan_downgrade_date
      )
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.schedule_copilot_plan_downgrade",
      ).length
    end
  end
end if GitHub.copilot_enabled?
