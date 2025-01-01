# typed: strict
# frozen_string_literal: true

require "test_helper"

class CopilotBusinessesSettingsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    @mailer = T.let(mock, T.nilable(Mocha::Mock))
    T.must(@mailer).stubs(:deliver_later)
  end

  context "#telemetry_aggregation_no_policy!" do
    test "sets to no policy" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_no_policy!

      assert copilot_business.telemetry_aggregation_no_policy?
    end
  end

  context "telemetry_aggregation_disabled!" do
    test "changes child orgs" do
      organization = create(:copilot_for_business_enabled_organization)
      copilot_org = Copilot::Organization.new(organization)
      copilot_org.ensure_configuration!

      copilot_business = Copilot::Business.new(organization.business)
      copilot_business.telemetry_aggregation_enabled!

      copilot_org = Copilot::Organization.new(organization)
      copilot_org.telemetry_aggregation_enabled!

      assert copilot_org.telemetry_aggregation_enabled?

      copilot_business.telemetry_aggregation_disabled!
      copilot_org = Copilot::Organization.new(organization.reload)
      refute copilot_org.telemetry_aggregation_enabled?
      assert copilot_org.usage_telemetry_api == "disabled"
    end
  end

  test "configuration defaults" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)
    copilot_business.ensure_configuration!
    configuration = Copilot::Configuration.find_by!(configurable: business)

    assert_subset_hash({
      "public_code_suggestions" => "no_policy",
      "user_telemetry" => "disabled",
      "chat_enabled" => "no_policy",
      "custom_models" => "unconfigured",
      "dotcom_chat" => "unconfigured",
      "cli" => "unconfigured",
      "pr_summarizations" => "unconfigured",
      "max_seats" => 1000,
    }, configuration.attributes)
  end

  context "max seats" do
    test "reads from the configuration, which defaults to 1000" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      assert_equal Copilot::COPILOT_ENTERPRISE_TEAM_MAX_SEATS_DEFAULT, copilot_business.copilot_max_seats
    end

    test "reads from the configuration, which can be set" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      copilot_business.copilot_max_seats = 999
      assert_equal 999, copilot_business.copilot_max_seats
    end
  end

  context "copilot enabled" do
    test "default value is disabled" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      assert copilot_business.copilot_disabled?
      assert_equal 0,
        copilot_business.copilot_enabled_organizations_count
    end

    test "enabling for all organizations" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:cfb_enabled_by_business)
        .with(business, org1)
        .returns(mailer)
        .once

      CopilotForBusinessMailer
        .expects(:cfb_enabled_by_business)
        .with(business, org2)
        .returns(mailer)
        .once

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).twice
      copilot_business.enable_copilot_for_all_organizations!(business.owners.first)

      refute copilot_business.copilot_disabled?
      assert copilot_business.copilot_enabled_for_all_organizations?
      refute copilot_business.copilot_enabled_for_selected_organizations?

      assert Copilot::Organization.new(org1).copilot_enabled?
      assert Copilot::Organization.new(org2).copilot_enabled?

      assert_equal 2,
        copilot_business.copilot_enabled_organizations_count

      org3 = create(:organization)
      Copilot::Organization.new(org3).ensure_configuration!
      business.add_organization(org3)
      org3.reload

      assert Copilot::Organization.new(org3).copilot_enabled?,
        "copilot is enabled for new organizations added to the business"
      assert_equal 3,
        copilot_business.copilot_enabled_organizations_count
    end

    context "business on a copilot enterprise plan" do
      test "enabling for an organization" do
        business = create(:business)
        copilot_business = Copilot::Business.new(business)
        copilot_business.copilot_plan_enterprise!

        org = create(:organization, business: business)

        mailer = mock
        mailer.stubs(:deliver_later)

        CopilotEnterpriseMailer
          .expects(:welcome_org_admins)
          .with(org)
          .returns(mailer)
          .once

        assert Copilot::Organization.new(org).copilot_disabled?

        ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
        copilot_business.enable_copilot_for_all_organizations!(business.owners.first)

        refute copilot_business.copilot_disabled?
        assert copilot_business.copilot_enabled_for_all_organizations?
        refute copilot_business.copilot_enabled_for_selected_organizations?

        assert Copilot::Organization.new(org).copilot_enabled?

        assert_equal 1, copilot_business.copilot_enabled_organizations_count
      end
    end

    test "enabling for all organizations when some were already enabled" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)

      copilot_business.enable_copilot_for_selected_organizations!([
        org1.id,
      ])

      assert_equal 1,
        copilot_business.copilot_enabled_organizations_count

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:cfb_enabled_by_business)
        .with(business, org2)
        .returns(mailer)
        .once

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once
      copilot_business.enable_copilot_for_all_organizations!(business.owners.first)

      refute copilot_business.copilot_disabled?
      assert copilot_business.copilot_enabled_for_all_organizations?
      refute copilot_business.copilot_enabled_for_selected_organizations?

      assert_equal 2,
        copilot_business.copilot_enabled_organizations_count

      assert Copilot::Organization.new(org1).copilot_enabled?
      assert Copilot::Organization.new(org2).copilot_enabled?
    end

    test "enabling for selected organizations" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      org3 = create(:organization, business: business)

      copilot_org3 = Copilot::Organization.new(org3)
      assert copilot_org3.copilot_disabled?

      old_settings = copilot_org3.copilot_organization_settings
      new_settings = old_settings.merge(copilot_enabled_setting: :COPILOT_ENABLED)

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once.with(org3, business.owners.first, old_settings: old_settings, new_settings: new_settings)
      copilot_business.enable_copilot_for_selected_organizations!([
        org3.id,
      ], business.owners.first)

      assert_equal 1,
        copilot_business.copilot_enabled_organizations_count

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:cfb_enabled_by_business)
        .with(business, org2)
        .returns(mailer)
        .once

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once

      copilot_business.enable_copilot_for_selected_organizations!([
        org2.id,
      ], business.owners.first)

      refute copilot_business.copilot_disabled?
      refute copilot_business.copilot_enabled_for_all_organizations?
      assert copilot_business.copilot_enabled_for_selected_organizations?

      refute Copilot::Organization.new(org1).copilot_enabled?,
        "does not touch other organizations"
      assert Copilot::Organization.new(org2).copilot_enabled?,
        "sets enabled for the given org"
      assert Copilot::Organization.new(org3).copilot_enabled?,
        "does not clobber the existing org"

      assert_equal 2,
        copilot_business.copilot_enabled_organizations_count
    end

    test "disabling" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)

      copilot_business.enable_copilot_for_selected_organizations!([
        org1.id
      ])

      assert_equal 1,
        copilot_business.copilot_enabled_organizations_count

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:cfb_disabled_by_business)
        .with(business, org1)
        .returns(mailer)
        .once


      copilot_business.disable_copilot!(business.owners.first)

      assert copilot_business.copilot_disabled?
      refute copilot_business.copilot_enabled_for_all_organizations?
      refute copilot_business.copilot_enabled_for_selected_organizations?

      refute Copilot::Organization.new(org1).copilot_enabled?
      refute Copilot::Organization.new(org2).copilot_enabled?

      assert_equal 0,
        copilot_business.copilot_enabled_organizations_count

      org3 = create(:organization)
      Copilot::Organization.new(org3).enable_copilot!(org3.admins.first)
      business.add_organization(org3)
      org3.reload

      refute Copilot::Organization.new(org3).copilot_enabled?,
        "copilot is disabled for new organizations added to the business"
      assert_equal 0,
        copilot_business.copilot_enabled_organizations_count
    end

    test "disabling for selected organizations" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)

      copilot_business.enable_copilot_for_all_organizations!

      assert_equal 2,
        copilot_business.copilot_enabled_organizations_count

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotForBusinessMailer
        .expects(:cfb_disabled_by_business)
        .with(business, org1)
        .returns(mailer)
        .once

      ::Copilot::Instrumenter.expects(:instrument_organization_settings_changed).once

      copilot_business.disable_copilot_for_selected_organizations!([
        org1.id
      ], business.owners.first)

      assert copilot_business.copilot_enabled_for_selected_organizations?

      refute Copilot::Organization.new(org1).copilot_enabled?,
        "sets disabled for the given org"
      assert Copilot::Organization.new(org2).copilot_enabled?,
        "does not touch other organizations"

      assert_equal 1,
        copilot_business.copilot_enabled_organizations_count

      org3 = create(:organization)
      business.add_organization(org3)
      org3.reload

      refute Copilot::Organization.new(org3).copilot_enabled?,
        "copilot is disabled for new organizations added to the business"
      assert_equal 1,
        copilot_business.copilot_enabled_organizations_count
    end
  end

  context "public code suggestions" do
    test "setting creates configuration record" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      assert_changes -> { Copilot::Configuration.count }, from: 0, to: 1 do
        copilot_business.allow_public_code_suggestions!
      end
    end

    test "defaults to snippy no_policy" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      refute copilot_business.allow_public_code_suggestions?
      refute copilot_business.block_public_code_suggestions?
      assert copilot_business.public_code_suggestions_configured?
      assert copilot_business.no_public_code_suggestions_policy?
      assert_equal "no_policy", copilot_business.snippy_setting
    end

    test "enabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      business = create(:business)
      org = create(:organization, business: business)

      copilot_business = Copilot::Business.new(business)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :business, configurable: business
      )

      assert copilot_business.public_code_suggestions_configured?
      refute copilot_org.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_no_policy?

      copilot_business.block_public_code_suggestions!
      copilot_business.disable_chat!
      copilot_business.disable_dotcom_chat!
      copilot_business.pr_summarizations_disabled!
      copilot_business.private_docs_disabled!
      copilot_business.cli_disabled!
      copilot_org = Copilot::Organization.new(org) # reload

      assert configuration.reload.public_code_suggestions_blocked?

      assert copilot_business.chat_disabled?
      assert copilot_business.dotcom_chat_disabled?
      assert copilot_business.pr_summarizations_disabled?
      assert copilot_business.private_docs_disabled?
      assert copilot_business.public_code_suggestions_configured?
      assert copilot_business.block_public_code_suggestions?
      refute copilot_business.allow_public_code_suggestions?
      refute copilot_business.no_public_code_suggestions_policy?
      assert_equal "enabled", copilot_business.snippy_setting

      assert copilot_org.block_public_code_suggestions?,
        "propagates block setting to orgs"

      assert copilot_org.chat_disabled?, "propagates disable of chat to orgs"
      assert copilot_org.dotcom_chat_disabled?, "propagates disable of dotcom chat to orgs"
      assert copilot_org.pr_summarizations_disabled?, "propagates disable of pr summarizations to orgs"
      assert copilot_org.private_docs_disabled?, "propagates disable of private docs to orgs"
      assert copilot_org.cli_disabled?, "propagates disable of cli to orgs"

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_blocked",
        tags: ["type:business"],
      ).length
      assert_equal 6, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_blocked",
        tags: ["type:organization"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.chat_enabled_disabled",
        tags: ["type:business"],
      ).length
      assert_equal 5, GitHub.dogstats.increments(
        "copilot.settings.chat_enabled_disabled",
        tags: ["type:organization"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.dotcom_chat_disabled",
        tags: ["type:business"],
      ).length
      assert_equal 4, GitHub.dogstats.increments(
        "copilot.settings.dotcom_chat_disabled",
        tags: ["type:organization"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.pr_summarizations_disabled",
        tags: ["type:business"],
      ).length
      assert_equal 3, GitHub.dogstats.increments(
        "copilot.settings.pr_summarizations_disabled",
        tags: ["type:organization"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.private_docs_disabled",
        tags: ["type:business"],
      ).length
      assert_equal 2, GitHub.dogstats.increments(
        "copilot.settings.private_docs_disabled",
        tags: ["type:organization"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.cli_disabled",
        tags: ["type:business"],
      ).length
      assert_equal 6, GitHub.dogstats.increments(
        "copilot.settings.cli_disabled",
        tags: ["type:organization"],
      ).length
    end

    test "disabling snippy" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      business = create(:business)
      org = create(:organization, business: business)

      copilot_business = Copilot::Business.new(business)
      copilot_org = Copilot::Organization.new(org)

      configuration = create(
        :copilot_configuration, :business, configurable: business
      )

      assert copilot_business.public_code_suggestions_configured?
      refute copilot_org.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_no_policy?

      copilot_business.allow_public_code_suggestions!
      copilot_org = Copilot::Organization.new(org) # reload

      assert configuration.reload.public_code_suggestions_allowed?

      assert copilot_business.public_code_suggestions_configured?
      refute copilot_business.block_public_code_suggestions?
      assert copilot_business.allow_public_code_suggestions?
      refute copilot_business.no_public_code_suggestions_policy?
      assert_equal "disabled", copilot_business.snippy_setting

      assert copilot_org.allow_public_code_suggestions?,
        "propagates allow setting to orgs"

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_allowed",
        tags: ["type:business"],
      ).length
      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.public_code_suggestions_allowed",
        tags: ["type:organization"],
      ).length
    end

    test "explicit no policy" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      configuration = create(
        :copilot_configuration, :business, configurable: business,
        public_code_suggestions: :allowed
      )

      assert copilot_business.allow_public_code_suggestions?
      assert copilot_business.public_code_suggestions_configured?
      refute copilot_business.no_public_code_suggestions_policy?
      refute configuration.public_code_suggestions_no_policy?

      copilot_business.no_public_code_suggestions_policy!

      assert configuration.reload.public_code_suggestions_no_policy?

      assert copilot_business.public_code_suggestions_configured?
      assert copilot_business.no_public_code_suggestions_policy?
      assert_equal "no_policy", copilot_business.snippy_setting
      assert copilot_business.no_chat_policy?
      assert copilot_business.dotcom_chat_no_policy?
      assert copilot_business.pr_summarizations_no_policy?
      assert copilot_business.private_docs_no_policy?
    end
  end

  test "default chat setting" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    assert copilot_business.chat_enabled_configured?
    assert copilot_business.dotcom_chat_unconfigured?
    assert copilot_business.pr_summarizations_unconfigured?
  end

  test "explicit chat no policy setting" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)
    org = create(:organization, business: business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.copilot_for_dotcom_disabled!

    CopilotForBusinessMailer.expects(:chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotMobileChatMailer.expects(:mobile_chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.no_chat_policy!

    assert_equal "no_policy", copilot_business.chat_setting
    assert copilot_business.no_chat_policy?
  end

  test "enabling chat" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.copilot_for_dotcom_disabled!

    CopilotForBusinessMailer.expects(:chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).once
    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.enable_chat!

    assert_equal "enabled", copilot_business.chat_setting
    assert copilot_business.chat_enabled?
  end

  test "disabling chat" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.copilot_for_dotcom_disabled!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    copilot_business.disable_chat!

    assert_equal "disabled", copilot_business.chat_setting
    assert copilot_business.chat_disabled?
  end

  test "enabling dotcom chat" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.dotcom_chat_enabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.dotcom_chat_setting
    assert_equal "enabled", copilot_org.dotcom_chat_setting
    assert_equal "enabled", copilot_user.dotcom_chat_setting
    assert copilot_business.dotcom_chat_enabled?
    assert copilot_org.dotcom_chat_enabled?
    assert copilot_user.dotcom_chat_enabled?
    refute copilot_user.dotcom_chat_disabled?
  end

  test "disabling dotcom chat" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.disable_dotcom_chat!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.dotcom_chat_setting
    assert_equal "disabled", copilot_org.dotcom_chat_setting
    assert_equal "disabled", copilot_user.dotcom_chat_setting
    assert copilot_business.dotcom_chat_disabled?
    assert copilot_org.dotcom_chat_disabled?
    assert copilot_user.dotcom_chat_disabled?
    refute copilot_user.dotcom_chat_enabled?
  end

  test "enabling pr summarizations" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.pr_summarizations_enabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.pr_summarizations_setting
    assert_equal "enabled", copilot_org.pr_summarizations_setting
    assert_equal "enabled", copilot_user.pr_summarizations_setting
    assert copilot_business.pr_summarizations_enabled?
    assert copilot_org.pr_summarizations_enabled?
    assert copilot_user.pr_summarizations_enabled?
    refute copilot_user.pr_summarizations_disabled?
  end

  test "disabling pr summarizations" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.pr_summarizations_disabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.pr_summarizations_setting
    assert_equal "disabled", copilot_org.pr_summarizations_setting
    assert_equal "disabled", copilot_user.pr_summarizations_setting
    assert copilot_business.pr_summarizations_disabled?
    assert copilot_org.pr_summarizations_disabled?
    assert copilot_user.pr_summarizations_disabled?
    refute copilot_user.pr_summarizations_enabled?
  end

  test "enabling private docs" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.private_docs_enabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.private_docs_setting
    assert_equal "enabled", copilot_org.private_docs_setting
    assert_equal "enabled", copilot_user.private_docs_setting
    assert copilot_business.private_docs_enabled?
    assert copilot_org.private_docs_enabled?
    assert copilot_user.private_docs_enabled?
    refute copilot_user.private_docs_disabled?
  end

  test "disabling private docs" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.cli_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.private_docs_disabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.private_docs_setting
    assert_equal "disabled", copilot_org.private_docs_setting
    assert_equal "disabled", copilot_user.private_docs_setting
    assert copilot_business.private_docs_disabled?
    assert copilot_org.private_docs_disabled?
    assert copilot_user.private_docs_disabled?
    refute copilot_user.private_docs_enabled?
  end

  test "default cli setting" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    assert copilot_business.cli_unconfigured?
  end

  test "enabling cli" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.copilot_for_dotcom_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:cli_enabled_for_user).with(org, seat.assigned_user).returns(mailer).once
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    copilot_business.cli_enabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.cli_setting
    assert_equal "enabled", copilot_org.cli_setting
    assert_equal "enabled", copilot_user.cli_setting
    assert copilot_business.cli_enabled?
    assert copilot_org.cli_enabled?
    assert copilot_user.cli_enabled?
    refute copilot_user.cli_disabled?
  end

  test "disabling cli" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    copilot_business.copilot_for_dotcom_disabled!
    copilot_business.disable_chat!

    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    copilot_business.cli_disabled!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.cli_setting
    assert_equal "disabled", copilot_org.cli_setting
    assert_equal "disabled", copilot_user.cli_setting
    assert copilot_business.cli_disabled?
    assert copilot_org.cli_disabled?
    assert copilot_user.cli_disabled?
    refute copilot_user.cli_enabled?
  end

  test "default private telemetry setting" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    assert copilot_business.private_telemetry_unconfigured?
  end

  test "enabling private telemetry" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    copilot_business.private_telemetry_enabled!

    assert_equal "enabled", copilot_business.private_telemetry_setting
    assert copilot_business.private_telemetry_enabled?
  end

  test "disabling private telemetry" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    copilot_business.private_telemetry_disabled!

    assert_equal "disabled", copilot_business.private_telemetry_setting
    assert copilot_business.private_telemetry_disabled?
  end

  test "enabling mobile_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotMobileChatMailer.expects(:mobile_chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    copilot_business.enable_mobile_chat!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.mobile_chat_setting
    assert_equal "enabled", copilot_org.mobile_chat_setting
    assert_equal "enabled", copilot_user.mobile_chat_setting
    assert copilot_business.mobile_chat_enabled?
    assert copilot_org.mobile_chat_enabled?
    assert copilot_user.mobile_chat_enabled?
    refute copilot_user.mobile_chat_disabled?
  end

  test "disabling mobile_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotMobileChatMailer.expects(:mobile_chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    copilot_business.disable_mobile_chat!

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.mobile_chat_setting
    assert_equal "disabled", copilot_org.mobile_chat_setting
    assert_equal "disabled", copilot_user.mobile_chat_setting
    refute copilot_business.mobile_chat_enabled?
    refute copilot_org.mobile_chat_enabled?
    refute copilot_user.mobile_chat_enabled?
    assert copilot_business.mobile_chat_disabled?
    assert copilot_org.mobile_chat_disabled?
    assert copilot_user.mobile_chat_disabled?
  end

  test "has_copilot_organization? returns true if an org has copilot enabled" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)
    create(:organization, business: business)
    create(:organization, business: business)
    refute copilot_business.has_copilot_organization?
  end

  test "has_copilot_organization? returns false if org does not have copilot enabled" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)
    create(:organization, business: business)
    create(:organization, business: business)
    copilot_business.enable_copilot_for_all_organizations!
    assert copilot_business.has_copilot_organization?
  end


  context "fine-tuning" do
    test "enabling" do
      GitHub.flipper[:copilot_for_enterprise].enable
      business = create(:business)
      org = create(:organization, business: business)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)
      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.copilot_for_dotcom_disabled!
      copilot_business.disable_chat!

      CopilotForBusinessMailer.expects(:chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotMobileChatMailer.expects(:mobile_chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

      copilot_business.custom_models_enabled!

      assert copilot_business.custom_models_enabled?
    end

    test "disabling" do
      GitHub.flipper[:copilot_for_enterprise].enable
      business = create(:business)
      org = create(:organization, business: business)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)
      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.copilot_for_dotcom_disabled!
      copilot_business.disable_chat!

      CopilotForBusinessMailer.expects(:chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotMobileChatMailer.expects(:mobile_chat_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

      copilot_business.custom_models_disabled!

      refute copilot_business.custom_models_enabled?
    end
  end

  context "#copilot_for_dotcom_unconfigured!" do
    test "sets all copilot for dotcom features to unconfigured but does not propagate to orgs" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      copilot_business = Copilot::Business.new(business)

      copilot_business.copilot_for_dotcom_unconfigured!

      assert copilot_business.copilot_for_dotcom_unconfigured?
      assert biz_config.reload.dotcom_chat_unconfigured?
      assert org_config.reload.dotcom_chat_enabled?
      assert biz_config.reload.pr_summarizations_unconfigured?
      assert org_config.reload.pr_summarizations_enabled?
    end
  end

  context "#copilot_for_dotcom_disabled!" do
    test "sets all copilot for dotcom features to disabled and propagates to orgs when the enterprise has the copilot_for_enterprise flag enabled" do
      business = create(:business)
      GitHub.flipper[:copilot_for_enterprise].enable(business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)

      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.disable_chat!
      copilot_business.cli_disabled!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(mailer).once

      copilot_business.copilot_for_dotcom_disabled!

      assert copilot_business.copilot_for_dotcom_disabled?
      assert biz_config.reload.dotcom_chat_disabled?
      assert org_config.reload.dotcom_chat_disabled?
      assert biz_config.reload.pr_summarizations_disabled?
      assert org_config.reload.pr_summarizations_disabled?
    end

    test "sets all copilot for dotcom features to disabled and propagates to orgs when the enterprise had an organization with a Copilot Enterprise trial" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_business_trial, :organization, copilot_plan: "enterprise", state: "expired", trialable: org)
      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.copilot_plan_business!
      copilot_business.copilot_for_dotcom_no_policy!
      Copilot::Organization.new(org).copilot_for_dotcom_enabled!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:trial_expired_for_user).with(org, seat.assigned_user).returns(mailer).once
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(mailer).never

      copilot_business.copilot_for_dotcom_disabled!
      assert copilot_business.copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(org).copilot_for_dotcom_disabled?
      assert biz_config.reload.dotcom_chat_disabled?
      assert org_config.reload.dotcom_chat_disabled?
      assert biz_config.reload.pr_summarizations_disabled?
      assert org_config.reload.pr_summarizations_disabled?
    end

    test "sets all copilot for dotcom features to disabled and propagates to orgs when the enterprise disables Copilot in github.com for all organizations" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_enabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_enabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)
      Copilot::Organization.any_instance.stubs(:copilot_billable?).returns(true)
      create(:copilot_business_trial, :organization, copilot_plan: "enterprise", state: "expired", trialable: org)
      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.copilot_for_dotcom_no_policy!
      Copilot::Organization.new(org).copilot_for_dotcom_enabled!
      copilot_business.copilot_plan_enterprise!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:trial_expired_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(mailer).once

      copilot_business.copilot_for_dotcom_disabled!
      assert copilot_business.copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(org).copilot_for_dotcom_disabled?
      assert biz_config.reload.dotcom_chat_disabled?
      assert org_config.reload.dotcom_chat_disabled?
      assert biz_config.reload.pr_summarizations_disabled?
      assert org_config.reload.pr_summarizations_disabled?
    end
  end

  context "#copilot_for_dotcom_enabled!" do
    test "sets all copilot for dotcom features to enabled and propagates to orgs when the enterprise has the copilot_for_enterprise flag enabled" do
      business = create(:business)
      GitHub.flipper[:copilot_for_enterprise].enable(business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_disabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)

      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.disable_chat!
      copilot_business.cli_disabled!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(mailer).once
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(mailer).never

      copilot_business.copilot_for_dotcom_enabled!

      assert copilot_business.copilot_for_dotcom_enabled?
      assert biz_config.reload.dotcom_chat_enabled?
      assert org_config.reload.dotcom_chat_enabled?
      assert biz_config.reload.pr_summarizations_enabled?
      assert org_config.reload.pr_summarizations_enabled?
    end

    test "sets all copilot for dotcom features to enabled and propagates to orgs when the enterprise has a copilot_enterprise plan" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_disabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      copilot_business.copilot_plan_enterprise!
      seat = create(:copilot_seat, organization: org)

      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.disable_chat!
      copilot_business.cli_disabled!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(mailer).once

      copilot_business.copilot_for_dotcom_enabled!

      assert copilot_business.copilot_for_dotcom_enabled?
      assert biz_config.reload.dotcom_chat_enabled?
      assert org_config.reload.dotcom_chat_enabled?
      assert biz_config.reload.pr_summarizations_enabled?
      assert org_config.reload.pr_summarizations_enabled?
    end

    test "does not send an email when organization doesn't have an enterprise plan under mixed licenses" do
      GitHub.flipper[:copilot_mixed_licenses].enable

      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_disabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      copilot_business.copilot_plan_enterprise!
      Copilot::Organization.new(org).copilot_plan_business!
      seat = create(:copilot_seat, organization: org)

      mailer = mock
      mailer.stubs(:deliver_later)

      copilot_business.disable_chat!
      copilot_business.cli_disabled!

      CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(mailer).never

      copilot_business.copilot_for_dotcom_enabled!

      assert copilot_business.copilot_for_dotcom_enabled?
      assert biz_config.reload.dotcom_chat_enabled?
      assert org_config.reload.dotcom_chat_enabled?
      assert biz_config.reload.pr_summarizations_enabled?
      assert org_config.reload.pr_summarizations_enabled?
    end
  end

  context "#copilot_for_dotcom_no_policy!" do
    test "sets all copilot for dotcom features to no_policy but does not propagate to orgs" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, :copilot_for_dotcom_disabled, configurable: business)
      org = create(:organization, business: business)
      org_config = create(:copilot_configuration, :organization, :copilot_for_dotcom_disabled, configurable: org)
      copilot_business = Copilot::Business.new(business)
      seat = create(:copilot_seat, organization: org)

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user).returns(mailer).never

      copilot_business.copilot_for_dotcom_no_policy!

      assert copilot_business.copilot_for_dotcom_no_policy?
      assert biz_config.reload.dotcom_chat_no_policy?
      assert org_config.reload.dotcom_chat_disabled?
      assert biz_config.reload.pr_summarizations_no_policy?
      assert org_config.reload.pr_summarizations_disabled?
    end

    test "sets all copilot for dotcom features to no_policy and disables for non-trial orgs when disable_non_trial_orgs_setting: true" do
      business = create(:business)
      biz_config = create(:copilot_configuration, :business, configurable: business)
      org = create(:copilot_for_business_enabled_organization, business: business)
      create(:copilot_business_trial, :organization, :recently_started, trialable: org)
      seat = create(:copilot_seat, organization: org)
      org2 = create(:organization, business: business)
      copilot_business = Copilot::Business.new(business)
      copilot_organization = Copilot::Organization.new(org)
      copilot_organization2 = Copilot::Organization.new(org2)

      business.reload

      copilot_business.copilot_for_dotcom_enabled!
      assert copilot_business.copilot_for_dotcom_enabled?
      assert copilot_organization.copilot_for_dotcom_enabled?
      assert copilot_organization2.copilot_for_dotcom_enabled?

      mailer = mock
      mailer.stubs(:deliver_later)

      CopilotEnterpriseMailer.expects(:cfe_enabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user).returns(mailer).never

      copilot_business.copilot_for_dotcom_no_policy!(disable_non_trial_orgs_setting: true)
      assert copilot_business.copilot_for_dotcom_no_policy?
      assert biz_config.reload.dotcom_chat_no_policy?
      assert biz_config.reload.pr_summarizations_no_policy?
      assert Copilot::Organization.new(org).copilot_for_dotcom_enabled? # Retains the trial org's Copilot in github.com policy
      assert Copilot::Organization.new(org).dotcom_chat_enabled?
      assert Copilot::Organization.new(org).pr_summarizations_enabled?
      assert Copilot::Organization.new(org2).copilot_for_dotcom_disabled? # Disables the non-trial org's Copilot in github.com policy
      assert Copilot::Organization.new(org2).dotcom_chat_disabled?
      assert Copilot::Organization.new(org2).pr_summarizations_disabled?
    end
  end

  context "bing skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.bing_github_chat_no_policy?
      refute biz.bing_github_chat_enabled?
      refute biz.bing_github_chat_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.bing_github_chat_no_policy?

      biz.bing_github_chat_enable!
      assert biz.bing_github_chat_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.bing_github_chat_no_policy?

      biz.bing_github_chat_disable!
      assert biz.bing_github_chat_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.bing_github_chat_no_policy?

      biz.bing_github_chat_enable!
      assert biz.bing_github_chat_enabled?

      biz.bing_github_chat_no_policy!
      assert biz.bing_github_chat_no_policy?
    end
  end

  context "beta_features skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.beta_features_github_chat_disabled?
      refute biz.beta_features_github_chat_no_policy?
      refute biz.beta_features_github_chat_enabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.beta_features_github_chat_disabled?

      biz.beta_features_github_chat_enable!
      assert biz.beta_features_github_chat_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.beta_features_github_chat_disabled?

      biz.beta_features_github_chat_disable!
      assert biz.beta_features_github_chat_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.beta_features_github_chat_disabled?

      biz.beta_features_github_chat_enable!
      assert biz.beta_features_github_chat_enabled?

      biz.copilot_for_dotcom_no_policy!
      assert biz.beta_features_github_chat_no_policy?
    end
  end

  context "#has_copilot_enterprise_access?" do
    test "is false if none of the flags are enabled" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      refute copilot_business.has_copilot_enterprise_access?
    end

    test "is true if the business has the copilot_for_enterprise flag enabled" do
      business = create(:business)
      GitHub.flipper[:copilot_for_enterprise].enable(business)
      copilot_business = Copilot::Business.new(business)
      assert copilot_business.has_copilot_enterprise_access?
    end

    test "is true if the business has a copilot enterprise plan" do
      copilot_business = create(:copilot_business, :enterprise_plan)
      assert copilot_business.has_copilot_enterprise_access?
    end
  end

  context "#copilot_enabled_members_count" do
    test "returns the number of enabled members" do
      business = create(:business)
      org1 = create(:organization, business: business)
      org2 = create(:organization, business: business)
      user1 = create(:user)
      user2 = create(:user)
      user3 = create(:user)
      org1.add_member(user1)
      org1.add_member(user2)
      org2.add_member(user1)
      org2.add_member(user3)
      create(:copilot_seat_assignment, organization: org1, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org1, assignable: user2).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user1).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: user3).convert_to_seats

      copilot_business = Copilot::Business.new(business.reload)
      # user1 has a seat in both orgs, but they should only count as one member
      assert_equal 3, copilot_business.copilot_enabled_members_count
    end
  end

  context "#eligible_to_migrate_to_enterprise_teams?" do
    test "returns true if business has all required betas and no enterprise teams" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns true if business has all required betas and direct managed enterprise copilot teams" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      enterprise_team = create(:enterprise_team, business: business)
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns true if business has all required betas and an IdP managed non-copilot enterprise team" do
      owner = create :emu, :owner
      business = owner.enterprise_managed_business
      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      enterprise_team = create(:enterprise_team, business: business)
      external_group = create(:external_group, :with_members, :with_team, business: business, number_of_members: 2)
      EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end if TestEnv.test_with_all_emus?

    test "returns false if business has all required betas and an IdP managed copilot team" do
      owner = create :emu, :owner
      business = owner.enterprise_managed_business
      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      enterprise_team = create(:enterprise_team, business: business)
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)
      external_group = create(:external_group, :with_members, :with_team, business: business, number_of_members: 2)
      EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end if TestEnv.test_with_all_emus?

    test "returns false if enterprise_teams_migrate_from_cfg is disabled" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable(business)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns false if business owns an org that cannot be deleted" do
      business = create(:business)
      create(:organization, business: business)
      Organization.any_instance.stubs(:permit_deletion?).returns(false)

      copilot_business = Copilot::Business.new(business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end
  end

  context "migrate_to_enterprise_teams" do
    test "doesn't work if enterprise_teams_migrate_from_cfg is disabled" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].disable(business)
      copilot_business = Copilot::Business.new(business)

      events = subscribe("enterprise_team.copilot.update")
      copilot_business.migrate_to_enterprise_teams

      event = events.pop
      assert_nil event
      assert_nil EnterpriseTeam.get_copilot_team(business)
    end

    test "does not continue to destroying org if copilot_organization.migrate_to_enterprise_teams returns false" do
      Copilot::Business.any_instance.expects(:migrate_to_enterprise_teams).at_least_once.returns(false)
      Organization.any_instance.expects(:async_destroy).never
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      events = subscribe("enterprise_team.copilot.update")
      copilot_business.migrate_to_enterprise_teams

      event = events.pop
      assert_nil event
      assert_nil EnterpriseTeam.get_copilot_team(business)
    end

    test "deletes organizations after migration" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)
      copilot_business = Copilot::Business.new(business)
      org = create(:organization, business: business)

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        copilot_business.migrate_to_enterprise_teams
      end

      assert_nil Organization.find_by(id: org.id)
    end

    test "deletes organizations without migrating if seat_management_disabled" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)
      copilot_business = Copilot::Business.new(business)
      org = create(:organization, business: business)
      copilot_organization = Copilot::Organization.new(org)
      copilot_organization.seat_management_disable!

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        assert_no_difference -> { EnterpriseTeam.count } do
          copilot_business.migrate_to_enterprise_teams
        end
      end

      assert_nil Organization.find_by(id: org.id)
    end

    test "adds users to enterprise team based on existing seat assignments" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      org1 = create(:copilot_for_business_enabled_organization, business: business)
      org1_user = create(:user)
      org1.add_member(org1_user)
      org2 = create(:copilot_for_business_enabled_organization, business: business.reload)
      org2_user1 = create(:user)
      org2_user2 = create(:user)
      org2.add_member(org2_user1)
      org2.add_member(org2_user2)

      org2_team = create(:team, organization: org2)
      org2_team.add_member(org2_user2)

      Copilot::Organization.new(org1).enable_copilot!
      Copilot::Organization.new(org2).enable_copilot!

      org_1_config = T.must(Copilot::Configuration.find_by(configurable_id: org1.id, configurable_type: "Organization"))
      org_2_config = T.must(Copilot::Configuration.find_by(configurable_id: org2.id, configurable_type: "Organization"))
      org_1_config.seat_management_enabled_for_all!
      org_2_config.seat_management_enabled_for_selected!

      create(:copilot_seat_assignment, organization: org1, assignable: org1, assigning_user: org1.admins.first).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: org2_user1, assigning_user: org2.admins.first).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: org2_team, assigning_user: org2.admins.first).convert_to_seats

      events = subscribe("enterprise_team.copilot.update")

      assert_difference -> { EnterpriseTeam.count }, 3 do
        Copilot::Business.new(business.reload).migrate_to_enterprise_teams
      end

      org_1_enterprise_team = EnterpriseTeam.find_by!(name: "#{org1.login}-#{EnterpriseTeam::COPILOT_TEAM_SUFFIX}")
      org_2_team_enterprise_team = EnterpriseTeam.find_by!(name: "#{org2.login}-#{org2_team.slug}-#{EnterpriseTeam::COPILOT_TEAM_SUFFIX}")
      org_2_direct_user_enterprise_team = EnterpriseTeam.find_by!(name: "#{org2.login}-#{EnterpriseTeam::COPILOT_TEAM_SUFFIX}")

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: org_2_direct_user_enterprise_team.id }, event.payload)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: org_2_team_enterprise_team.id }, event.payload)

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal({ id: org_1_enterprise_team.id }, event.payload)

      assert_equal 2, org_1_enterprise_team.member_user_ids.length
      assert_equal org_1_enterprise_team.member_user_ids, [org1.admins.first.id, org1_user.id]

      assert_equal 1, org_2_direct_user_enterprise_team.member_user_ids.length
      assert_equal org_2_direct_user_enterprise_team.member_user_ids, [org2_user1.id]

      assert_equal 1, org_2_team_enterprise_team.member_user_ids.length
      assert_equal org_2_team_enterprise_team.member_user_ids, [org2_user2.id]

      seat_assignments = Copilot::SeatAssignment.for_owner(business)
      assert_equal 3, seat_assignments.count
      assert_equal org_1_enterprise_team, seat_assignments.first.assignable
      assert_equal org_2_team_enterprise_team, seat_assignments.second&.assignable
      assert_equal org_2_direct_user_enterprise_team, seat_assignments.third&.assignable
    end

    test "calls copilot_org.migrate_to_enterprise_teams" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)
      copilot_business = Copilot::Business.new(business)

      org = create(:organization, business: business)
      copilot_org = Copilot::Organization.new(org)
      copilot_org.seat_management_allow_all!

      copilot_business.enable_copilot_for_all_organizations!(business.owners.first)

      Copilot::Organization.any_instance.expects(:migrate_to_enterprise_teams).once

      copilot_business.migrate_to_enterprise_teams
    end

    test "keeps existing users as unaffiliated after orgs are removed" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)

      org1 = create(:copilot_for_business_enabled_organization, business: business)
      org1_user = create(:user)
      org1.add_member(org1_user)
      org2 = create(:copilot_for_business_enabled_organization, business: business.reload)
      org2_user1 = create(:user)
      org2_user2 = create(:user)
      org2.add_member(org2_user1)
      org2.add_member(org2_user2)

      org2_team = create(:team, organization: org2)
      org2_team.add_member(org2_user2)

      Copilot::Organization.new(org1).enable_copilot!
      Copilot::Organization.new(org2).enable_copilot!

      org_1_config = T.must(Copilot::Configuration.find_by(configurable_id: org1.id, configurable_type: "Organization"))
      org_2_config = T.must(Copilot::Configuration.find_by(configurable_id: org2.id, configurable_type: "Organization"))
      org_1_config.seat_management_enabled_for_all!
      org_2_config.seat_management_enabled_for_selected!

      create(:copilot_seat_assignment, organization: org1, assignable: org1, assigning_user: org1.admins.first).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: org2_user1, assigning_user: org2.admins.first).convert_to_seats
      create(:copilot_seat_assignment, organization: org2, assignable: org2_team, assigning_user: org2.admins.first).convert_to_seats

      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: business.id)

      refute business.exclusive_unaffiliated_member?(org1_user)
      refute business.exclusive_unaffiliated_member?(org2_user1)
      refute business.exclusive_unaffiliated_member?(org2_user2)
      member_ids = business.user_accounts.pluck(:id)

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        Copilot::Business.new(business.reload).migrate_to_enterprise_teams
      end
      BusinessUserAccountUpdateAttributesJob.perform_now(business_id: business.reload.id)

      assert_equal member_ids, business.user_accounts.pluck(:id)
      assert business.exclusive_unaffiliated_member?(org1_user)
      assert business.exclusive_unaffiliated_member?(org2_user1)
      assert business.exclusive_unaffiliated_member?(org2_user2)
    end

    test "does not send org deletion emails" do
      business = create(:business)
      GitHub.flipper[:enterprise_teams_migrate_from_cfb].enable(business)
      copilot_business = Copilot::Business.new(business)
      org = create(:organization, business: business)

      assert_no_difference "ActionMailer::Base.deliveries.size" do
        perform_enqueued_jobs(only: [UserDeleteJob, ApplicationDeliveryJob]) do
          copilot_business.migrate_to_enterprise_teams
        end
      end

      assert_nil Organization.find_by(id: org.id)
    end
  end

  context "user feedback setting" do
    test "defaults to no policy if Copilot in dotcom chat has no policy" do
      biz = create(:copilot_business)
      biz.copilot_for_dotcom_no_policy!

      assert biz.user_feedback_opt_in_no_policy?
      refute biz.user_feedback_opt_in_enabled?
      refute biz.user_feedback_opt_in_disabled?
    end

    test "defaults to enabled if Copilot in dotcom chat is enabled" do
      biz = create(:copilot_business)
      biz.copilot_for_dotcom_enabled!

      assert biz.user_feedback_opt_in_enabled?
      refute biz.user_feedback_opt_in_no_policy?
      refute biz.user_feedback_opt_in_disabled?
    end

    test "always disabled if Copilot in dotcom chat is disabled" do
      biz = create(:copilot_business)
      biz.copilot_for_dotcom_disabled!
      biz.enable_user_feedback!

      assert biz.user_feedback_opt_in_disabled?
      refute biz.user_feedback_opt_in_no_policy?
      refute biz.user_feedback_opt_in_enabled?
    end

    test "can be disabled if Copilot in dotcom chat is enabled" do
      biz = create(:copilot_business)
      biz.copilot_for_dotcom_enabled!
      biz.disable_user_feedback!

      assert biz.user_feedback_opt_in_disabled?
      refute biz.user_feedback_opt_in_enabled?
      refute biz.user_feedback_opt_in_no_policy?
    end

    context "#disable_user_feedback!" do
      test "disables the user feedback policy on the business" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_business.copilot_for_dotcom_enabled!

        copilot_business.disable_user_feedback!

        refute Copilot::Business.new(organization.reload.business).user_feedback_opt_in_enabled?
      end
    end

    context "#enable_user_feedback!" do
      test "enables the user feedback policy on the business and its organizations" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_business.copilot_for_dotcom_enabled!

        copilot_business.enable_user_feedback!

        assert Copilot::Business.new(organization.reload.business).user_feedback_opt_in_enabled?
        assert Copilot::Organization.new(organization).user_feedback_opt_in_enabled?
      end
    end

    context "#copilot_extensions_enabled!" do
      test "enables copilot extensions for the business and its organizations" do
        biz = create(:business)
        biz_config = create(:copilot_configuration, :business, configurable: biz, copilot_extensions: :disabled)
        org = create(:organization, business: biz)
        org_config = create(:copilot_configuration, :organization, configurable: org, copilot_extensions: :disabled)
        copilot_biz = Copilot::Business.new(biz)
        copilot_org = Copilot::Organization.new(org)

        copilot_biz.copilot_extensions_enabled!

        assert copilot_biz.copilot_extensions_enabled?
        assert copilot_org.copilot_extensions_enabled?
        assert biz_config.reload.copilot_extensions_enabled?
        assert org_config.reload.copilot_extensions_enabled?
      end
    end

    context "#copilot_extensions_disabled!" do
      test "disables copilot extensions for the business and its organizations" do
        biz = create(:business)
        biz_config = create(:copilot_configuration, :business, configurable: biz, copilot_extensions: :enabled)
        org = create(:organization, business: biz)
        org_config = create(:copilot_configuration, :organization, configurable: org, copilot_extensions: :enabled)
        copilot_biz = Copilot::Business.new(biz)
        copilot_org = Copilot::Organization.new(org)

        copilot_biz.copilot_extensions_disabled!

        assert copilot_biz.copilot_extensions_disabled?
        assert copilot_org.copilot_extensions_disabled?
        assert biz_config.reload.copilot_extensions_disabled?
        assert org_config.reload.copilot_extensions_disabled?
      end
    end

    context "#copilot_extensions_no_policy!" do
      test "Sets no policy for copilot extensions for the business but not its organizations" do
        biz = create(:business)
        biz_config = create(:copilot_configuration, :business, configurable: biz, copilot_extensions: :enabled)
        org = create(:organization, business: biz)
        org_config = create(:copilot_configuration, :organization, configurable: org, copilot_extensions: :enabled)
        copilot_biz = Copilot::Business.new(biz)
        copilot_org = Copilot::Organization.new(org)

        copilot_biz.copilot_extensions_no_policy!

        assert copilot_biz.copilot_extensions_no_policy?
        assert copilot_org.copilot_extensions_enabled?
        assert biz_config.reload.copilot_extensions_no_policy?
        assert org_config.reload.copilot_extensions_enabled?
      end
    end

    context "#copilot_plan_downgrade!" do
      test "downgrades copilot plan from enterprise to business" do
        biz = create(:business)
        biz_config = create(
          :copilot_configuration,
          :business,
          configurable: biz,
          copilot_plan: :enterprise,
          dotcom_chat: :enabled,
          pr_summarizations: :enabled,
          github_enterprise_feature_group: :enabled,
          pending_plan_downgrade_date: 1.day.ago
        )
        copilot_biz = Copilot::Business.new(biz)

        copilot_biz.copilot_plan_downgrade!
        biz_config.reload

        assert_nil biz_config.pending_plan_downgrade_date
        assert biz_config.copilot_plan_business?
        assert biz_config.dotcom_chat_no_policy?
        assert biz_config.pr_summarizations_no_policy?
        assert biz_config.github_enterprise_feature_group_no_policy?
      end
    end
  end
end if GitHub.copilot_enabled?
