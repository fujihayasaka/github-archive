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
      "public_code_suggestions" => "blocked",
      "user_telemetry" => "disabled",
      "chat_enabled" => "enabled",
      "custom_models" => "unconfigured",
      "dotcom_chat" => "enabled",
      "cli" => "enabled",
      "pr_summarizations" => "enabled",
      "max_seats" => 1000,
      "desktop" => "enabled",
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

  context "#copilot" do
    test "allows setting to unconfigured" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      business = create(:business)

      Copilot::Business.new(business).copilot_unconfigured!

      assert_equal 1, GitHub.dogstats.increments(
        "copilot.settings.copilot_unconfigured",
        tags: ["type:business"],
      ).length
    end
  end

  context "copilot enabled" do
    test "default value is disabled for full enterprises" do
      disable_feature_flag(:copilot_enabled_unconfigured)
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      assert copilot_business.copilot_disabled?
      assert_equal 0,
        copilot_business.copilot_enabled_organizations_count
    end

    test "default value is disabled for standalone enterprises" do
      business = create(:business)
      business.update(seats_plan_type: :basic)
      copilot_business = Copilot::Business.new(business)

      assert copilot_business.copilot_disabled?
      assert_equal 0,
        copilot_business.copilot_enabled_organizations_count
    end

    test "default value is unconfigured when copilot_enabled_unconfigured is active" do
      enable_feature_flag(:copilot_enabled_unconfigured)
      business = create(:business)
      copilot_business = Copilot::Business.new(business)

      assert copilot_business.copilot_unconfigured?
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
      old_settings.merge!(pr_summarizations_setting: :PR_SUMMARIZATIONS_ENABLED)
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
      refute copilot_business.no_public_code_suggestions_policy?
      assert copilot_business.block_public_code_suggestions?
      assert copilot_business.public_code_suggestions_configured?
      assert_equal "enabled", copilot_business.snippy_setting
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
      assert configuration.public_code_suggestions_blocked?
      assert copilot_org.block_public_code_suggestions?

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.disable_chat!
        copilot_business.disable_dotcom_chat!
        copilot_business.pr_summarizations_disabled!
        copilot_business.private_docs_disabled!
        copilot_business.cli_disabled!
      end
      copilot_org = Copilot::Organization.new(org) # reload

      assert copilot_business.chat_disabled?
      assert copilot_business.dotcom_chat_disabled?
      assert copilot_business.pr_summarizations_disabled?
      assert copilot_business.private_docs_disabled?
      assert copilot_business.public_code_suggestions_configured?
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

      assert_equal 5, GitHub.dogstats.increments(
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
      assert_equal 5, GitHub.dogstats.increments(
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
      assert copilot_org.public_code_suggestions_configured?
      assert configuration.public_code_suggestions_blocked?

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.allow_public_code_suggestions!
      end
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
    assert copilot_business.dotcom_chat_enabled?
    assert copilot_business.pr_summarizations_enabled?
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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.enable_chat!
    end

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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.disable_chat!
    end

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
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    Copilot::Business.new(business).cli_disabled!
    Copilot::Business.new(business).disable_chat!
    T.must(Copilot::Configuration.where(configurable_id: business.id).take).github_enterprise_feature_group_unconfigured!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    Copilot::Business.new(business).disable_dotcom_chat!

    assert_equal "disabled", Copilot::Business.new(business).dotcom_chat_setting
    assert_equal "disabled", Copilot::Organization.new(org).dotcom_chat_setting
    assert_equal "disabled", Copilot::User.new(seat.assigned_user).dotcom_chat_setting
    assert Copilot::Business.new(business).dotcom_chat_disabled?
    assert Copilot::Organization.new(org).dotcom_chat_disabled?
    assert Copilot::User.new(seat.assigned_user).dotcom_chat_disabled?
    refute Copilot::User.new(seat.assigned_user).dotcom_chat_enabled?
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
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    Copilot::Business.new(business).cli_disabled!
    Copilot::Business.new(business).disable_chat!
    T.must(Copilot::Configuration.where(configurable_id: business.id).take).github_enterprise_feature_group_unconfigured!

    CopilotForBusinessMailer.expects(:cli_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotEnterpriseMailer.expects(:cfe_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
    CopilotForBusinessMailer.expects(:chat_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

    Copilot::Business.new(business).pr_summarizations_disabled!

    assert_equal "disabled", Copilot::Business.new(business).pr_summarizations_setting
    assert_equal "disabled", Copilot::Organization.new(org).pr_summarizations_setting
    assert_equal "disabled", Copilot::User.new(seat.assigned_user).pr_summarizations_setting
    assert Copilot::Business.new(business).pr_summarizations_disabled?
    assert Copilot::Organization.new(org).pr_summarizations_disabled?
    assert Copilot::User.new(seat.assigned_user).pr_summarizations_disabled?
    refute Copilot::User.new(seat.assigned_user).pr_summarizations_enabled?
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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.private_docs_enabled!
    end

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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.private_docs_disabled!
    end

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

    assert copilot_business.cli_enabled?
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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.cli_enabled!
    end

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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.cli_disabled!
    end

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

  test "default desktop setting" do
    business = create(:business)
    copilot_business = Copilot::Business.new(business)

    assert copilot_business.desktop_enabled?
  end

  test "enabling desktop" do
    enable_feature_flag(:copilot_desktop)

    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:desktop_enabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.desktop_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.desktop_setting
    assert_equal "enabled", copilot_org.desktop_setting
    assert_equal "enabled", copilot_user.desktop_setting
    assert copilot_business.desktop_enabled?
    assert copilot_org.desktop_enabled?
    assert copilot_user.desktop_enabled?
    refute copilot_user.desktop_disabled?
  end

  test "disabling desktop" do
    enable_feature_flag(:copilot_desktop)

    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)
    mailer = mock
    mailer.stubs(:deliver_later)

    CopilotForBusinessMailer.expects(:desktop_disabled_for_user).with(org, seat.assigned_user).returns(mailer).once

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.desktop_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.desktop_setting
    assert_equal "disabled", copilot_org.desktop_setting
    assert_equal "disabled", copilot_user.desktop_setting
    assert copilot_business.desktop_disabled?
    assert copilot_org.desktop_disabled?
    assert copilot_user.desktop_disabled?
    refute copilot_user.desktop_enabled?
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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.enable_mobile_chat!
    end

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

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.disable_mobile_chat!
    end

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

  test "enabling a_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.a_chat_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.a_chat_setting
    assert_equal "enabled", copilot_org.a_chat_setting
    assert_equal "enabled", copilot_user.a_chat_setting
    assert copilot_business.a_chat_enabled?
    assert copilot_org.a_chat_enabled?
    assert copilot_user.a_chat_enabled?
    refute copilot_user.a_chat_disabled?
  end

  test "disabling a_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.a_chat_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.a_chat_setting
    assert_equal "disabled", copilot_org.a_chat_setting
    assert_equal "disabled", copilot_user.a_chat_setting
    refute copilot_business.a_chat_enabled?
    refute copilot_org.a_chat_enabled?
    refute copilot_user.a_chat_enabled?
    assert copilot_business.a_chat_disabled?
    assert copilot_org.a_chat_disabled?
    assert copilot_user.a_chat_disabled?
  end

  test "enabling a_f in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.a_f_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.a_f_setting
    assert_equal "enabled", copilot_org.a_f_setting
    assert_equal "enabled", copilot_user.a_f_setting
    assert copilot_business.a_f_enabled?
    assert copilot_org.a_f_enabled?
    assert copilot_user.a_f_enabled?
    refute copilot_user.a_f_disabled?
  end

  test "disabling a_f in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.a_f_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.a_f_setting
    assert_equal "disabled", copilot_org.a_f_setting
    assert_equal "disabled", copilot_user.a_f_setting
    refute copilot_business.a_f_enabled?
    refute copilot_org.a_f_enabled?
    refute copilot_user.a_f_enabled?
    assert copilot_business.a_f_disabled?
    assert copilot_org.a_f_disabled?
    assert copilot_user.a_f_disabled?
  end

  test "enabling g_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.g_chat_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.g_chat_setting
    assert_equal "enabled", copilot_org.g_chat_setting
    assert_equal "enabled", copilot_user.g_chat_setting
    assert copilot_business.g_chat_enabled?
    assert copilot_org.g_chat_enabled?
    assert copilot_user.g_chat_enabled?
    refute copilot_user.g_chat_disabled?
  end

  test "disabling g_chat in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.g_chat_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.g_chat_setting
    assert_equal "disabled", copilot_org.g_chat_setting
    assert_equal "disabled", copilot_user.g_chat_setting
    refute copilot_business.g_chat_enabled?
    refute copilot_org.g_chat_enabled?
    refute copilot_user.g_chat_enabled?
    assert copilot_business.g_chat_disabled?
    assert copilot_org.g_chat_disabled?
    assert copilot_user.g_chat_disabled?
  end

  test "enabling next edit suggestion in GA" do
    enable_feature_flag(:copilot_next_edit_suggestions)
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.editor_preview_features_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.editor_preview_features_setting
    assert_equal "enabled", copilot_org.editor_preview_features_setting
    assert_equal "enabled", copilot_user.editor_preview_features_setting
    assert copilot_business.editor_preview_features_enabled?
    assert copilot_org.editor_preview_features_enabled?
    assert copilot_user.editor_preview_features_enabled?
    refute copilot_user.editor_preview_features_disabled?
  end

  test "disabling next edit suggestion in GA" do
    enable_feature_flag(:copilot_next_edit_suggestions)
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.editor_preview_features_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.editor_preview_features_setting
    assert_equal "disabled", copilot_org.editor_preview_features_setting
    assert_equal "disabled", copilot_user.editor_preview_features_setting
    refute copilot_business.editor_preview_features_enabled?
    refute copilot_org.editor_preview_features_enabled?
    refute copilot_user.editor_preview_features_enabled?
    assert copilot_business.editor_preview_features_disabled?
    assert copilot_org.editor_preview_features_disabled?
    assert copilot_user.editor_preview_features_disabled?
  end

  test "enabling o1 in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o1_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.o1_setting
    assert_equal "enabled", copilot_org.o1_setting
    assert_equal "enabled", copilot_user.o1_setting
    assert copilot_business.o1_enabled?
    assert copilot_org.o1_enabled?
    assert copilot_user.o1_enabled?
    refute copilot_user.o1_disabled?
  end

  test "disabling o1 in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o1_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.o1_setting
    assert_equal "disabled", copilot_org.o1_setting
    assert_equal "disabled", copilot_user.o1_setting
    refute copilot_business.o1_enabled?
    refute copilot_org.o1_enabled?
    refute copilot_user.o1_enabled?
    assert copilot_business.o1_disabled?
    assert copilot_org.o1_disabled?
    assert copilot_user.o1_disabled?
  end

  test "enabling o3 in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o3_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.o3_setting
    assert_equal "enabled", copilot_org.o3_setting
    assert_equal "enabled", copilot_user.o3_setting
    assert copilot_business.o3_enabled?
    assert copilot_org.o3_enabled?
    assert copilot_user.o3_enabled?
    refute copilot_user.o3_disabled?
  end

  test "disabling o3 in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o3_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.o3_setting
    assert_equal "disabled", copilot_org.o3_setting
    assert_equal "disabled", copilot_user.o3_setting
    refute copilot_business.o3_enabled?
    refute copilot_org.o3_enabled?
    refute copilot_user.o3_enabled?
    assert copilot_business.o3_disabled?
    assert copilot_org.o3_disabled?
    assert copilot_user.o3_disabled?
  end

  test "enabling o_ff in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o_ff_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.o_ff_setting
    assert_equal "enabled", copilot_org.o_ff_setting
    assert_equal "enabled", copilot_user.o_ff_setting
    assert copilot_business.o_ff_enabled?
    assert copilot_org.o_ff_enabled?
    assert copilot_user.o_ff_enabled?
    refute copilot_user.o_ff_disabled?
  end

  test "disabling o_ff in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o_ff_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.o_ff_setting
    assert_equal "disabled", copilot_org.o_ff_setting
    assert_equal "disabled", copilot_user.o_ff_setting
    refute copilot_business.o_ff_enabled?
    refute copilot_org.o_ff_enabled?
    refute copilot_user.o_ff_enabled?
    assert copilot_business.o_ff_disabled?
    assert copilot_org.o_ff_disabled?
    assert copilot_user.o_ff_disabled?
  end

  test "enabling o_f in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o_f_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.o_f_setting
    assert_equal "enabled", copilot_org.o_f_setting
    assert_equal "enabled", copilot_user.o_f_setting
    assert copilot_business.o_f_enabled?
    assert copilot_org.o_f_enabled?
    assert copilot_user.o_f_enabled?
    refute copilot_user.o_f_disabled?
  end

  test "disabling o_f in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.o_f_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.o_f_setting
    assert_equal "disabled", copilot_org.o_f_setting
    assert_equal "disabled", copilot_user.o_f_setting
    refute copilot_business.o_f_enabled?
    refute copilot_org.o_f_enabled?
    refute copilot_user.o_f_enabled?
    assert copilot_business.o_f_disabled?
    assert copilot_org.o_f_disabled?
    assert copilot_user.o_f_disabled?
  end

  test "enabling overages in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.overages_enabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "enabled", copilot_business.overages_setting
    assert_equal "enabled", copilot_org.overages_setting
    assert_equal "enabled", copilot_user.overages_setting
    assert copilot_business.overages_enabled?
    assert copilot_org.overages_enabled?
    assert copilot_user.overages_enabled?
    refute copilot_user.overages_disabled?
  end

  test "disabling overages in GA" do
    business = create(:business)
    org = create(:organization, business: business)
    copilot_business = Copilot::Business.new(business)
    seat = create(:copilot_seat, organization: org)

    perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
      copilot_business.overages_disabled!
    end

    copilot_org = Copilot::Organization.new(org)
    copilot_user = Copilot::User.new(seat.assigned_user)

    assert_equal "disabled", copilot_business.overages_setting
    assert_equal "disabled", copilot_org.overages_setting
    assert_equal "disabled", copilot_user.overages_setting
    refute copilot_business.overages_enabled?
    refute copilot_org.overages_enabled?
    refute copilot_user.overages_enabled?
    assert copilot_business.overages_disabled?
    assert copilot_org.overages_disabled?
    assert copilot_user.overages_disabled?
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
      enable_feature_flag(:copilot_for_enterprise)
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
      enable_feature_flag(:copilot_for_enterprise)
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

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_unconfigured!
      end

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
      enable_feature_flag(:copilot_for_enterprise, business)
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
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_disabled!
      end

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
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_user).with(org, seat.assigned_user).returns(mailer).never
      CopilotEnterpriseMailer.expects(:copilot_in_dotcom_disabled_for_organization).with(org).returns(mailer).never

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_disabled!
      end
      assert copilot_business.copilot_for_dotcom_disabled?
      assert Copilot::Organization.new(org).copilot_for_dotcom_disabled?
      assert biz_config.reload.dotcom_chat_disabled?
      assert org_config.reload.dotcom_chat_disabled?
      assert biz_config.reload.pr_summarizations_disabled?
      assert org_config.reload.pr_summarizations_disabled?
    end

    test "sets all copilot for dotcom features to disabled and propagates to orgs when the enterprise disables Copilot in GitHub.com for all organizations" do
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


      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_disabled!
      end
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
      enable_feature_flag(:copilot_for_enterprise, business)
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
      CopilotEnterpriseMailer.expects(:upgrade_individual).with(org, seat.assigned_user, false).returns(mailer).never

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_enabled!
      end

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

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_enabled!
      end

      assert copilot_business.copilot_for_dotcom_enabled?
      assert biz_config.reload.dotcom_chat_enabled?
      assert org_config.reload.dotcom_chat_enabled?
      assert biz_config.reload.pr_summarizations_enabled?
      assert org_config.reload.pr_summarizations_enabled?
    end

    test "does not send an email when enterprise-owned organization doesn't have an enterprise plan" do
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

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_enabled!
      end

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

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_no_policy!
      end

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

      perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
        copilot_business.copilot_for_dotcom_enabled!
      end
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
      assert Copilot::Organization.new(org).copilot_for_dotcom_enabled? # Retains the trial org's Copilot in GitHub.com policy
      assert Copilot::Organization.new(org).dotcom_chat_enabled?
      assert Copilot::Organization.new(org).pr_summarizations_enabled?
      assert Copilot::Organization.new(org2).copilot_for_dotcom_disabled? # Disables the non-trial org's Copilot in GitHub.com policy
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

  context "a_chat skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.a_chat_unconfigured?
      refute biz.a_chat_enabled?
      refute biz.a_chat_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.a_chat_unconfigured?

      biz.a_chat_enabled!
      assert biz.a_chat_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.a_chat_unconfigured?

      biz.a_chat_disabled!
      assert biz.a_chat_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.a_chat_unconfigured?

      biz.a_chat_enabled!
      assert biz.a_chat_enabled?

      biz.a_chat_no_policy!
      assert biz.a_chat_no_policy?
    end
  end

  context "a_f skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.a_f_unconfigured?
      refute biz.a_f_enabled?
      refute biz.a_f_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.a_f_unconfigured?

      biz.a_f_enabled!
      assert biz.a_f_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.a_f_unconfigured?

      biz.a_f_disabled!
      assert biz.a_f_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.a_f_unconfigured?

      biz.a_f_enabled!
      assert biz.a_f_enabled?

      biz.a_f_no_policy!
      assert biz.a_f_no_policy?
    end
  end

  context "g_chat skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.g_chat_unconfigured?
      refute biz.g_chat_enabled?
      refute biz.g_chat_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.g_chat_unconfigured?

      biz.g_chat_enabled!
      assert biz.g_chat_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.g_chat_unconfigured?

      biz.g_chat_disabled!
      assert biz.g_chat_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.g_chat_unconfigured?

      biz.g_chat_enabled!
      assert biz.g_chat_enabled?

      biz.g_chat_no_policy!
      assert biz.g_chat_no_policy?
    end
  end

  context "next edit suggestion skill state" do
    test "defaults to no policy" do
      enable_feature_flag(:copilot_next_edit_suggestions)
      biz = create(:copilot_business)

      assert biz.editor_preview_features_unconfigured?
      refute biz.editor_preview_features_enabled?
      refute biz.editor_preview_features_disabled?
    end

    test "is enableable" do
      enable_feature_flag(:copilot_next_edit_suggestions)
      biz = create(:copilot_business)
      assert biz.editor_preview_features_unconfigured?

      biz.editor_preview_features_enabled!
      assert biz.editor_preview_features_enabled?
    end

    test "is disableable" do
      enable_feature_flag(:copilot_next_edit_suggestions)
      biz = create(:copilot_business)
      assert biz.editor_preview_features_unconfigured?

      biz.editor_preview_features_disabled!
      assert biz.editor_preview_features_disabled?
    end

    test "can be returned to no policy" do
      enable_feature_flag(:copilot_next_edit_suggestions)
      biz = create(:copilot_business)
      assert biz.editor_preview_features_unconfigured?

      biz.editor_preview_features_enabled!
      assert biz.editor_preview_features_enabled?

      biz.editor_preview_features_no_policy!
      assert biz.editor_preview_features_no_policy?
    end
  end

  context "o1 skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.o1_unconfigured?
      refute biz.o1_enabled?
      refute biz.o1_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.o1_unconfigured?

      biz.o1_enabled!
      assert biz.o1_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.o1_unconfigured?

      biz.o1_disabled!
      assert biz.o1_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.o1_unconfigured?

      biz.o1_enabled!
      assert biz.o1_enabled?

      biz.o1_no_policy!
      assert biz.o1_no_policy?
    end
  end

  context "o3 skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.o3_unconfigured?
      refute biz.o3_enabled?
      refute biz.o3_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.o3_unconfigured?

      biz.o3_enabled!
      assert biz.o3_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.o3_unconfigured?

      biz.o3_disabled!
      assert biz.o3_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.o3_unconfigured?

      biz.o3_enabled!
      assert biz.o3_enabled?

      biz.o3_no_policy!
      assert biz.o3_no_policy?
    end
  end

  context "o_ff skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.o_ff_unconfigured?
      refute biz.o_ff_enabled?
      refute biz.o_ff_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.o_ff_unconfigured?

      biz.o_ff_enabled!
      assert biz.o_ff_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.o_ff_unconfigured?

      biz.o_ff_disabled!
      assert biz.o_ff_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.o_ff_unconfigured?

      biz.o_ff_enabled!
      assert biz.o_ff_enabled?

      biz.o_ff_no_policy!
      assert biz.o_ff_no_policy?
    end
  end

  context "o_f skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.o_f_unconfigured?
      refute biz.o_f_enabled?
      refute biz.o_f_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.o_f_unconfigured?

      biz.o_f_enabled!
      assert biz.o_f_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.o_f_unconfigured?

      biz.o_f_disabled!
      assert biz.o_f_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.o_f_unconfigured?

      biz.o_f_enabled!
      assert biz.o_f_enabled?

      biz.o_f_no_policy!
      assert biz.o_f_no_policy?
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

      biz.copilot_for_dotcom_disabled!
      biz.beta_features_github_chat_no_policy!
      assert biz.beta_features_github_chat_no_policy?
    end
  end

  context "overages skill state" do
    test "defaults to no policy" do
      biz = create(:copilot_business)

      assert biz.overages_unconfigured?
      refute biz.overages_enabled?
      refute biz.overages_disabled?
    end

    test "is enableable" do
      biz = create(:copilot_business)
      assert biz.overages_unconfigured?

      biz.overages_enabled!
      assert biz.overages_enabled?
    end

    test "is disableable" do
      biz = create(:copilot_business)
      assert biz.overages_unconfigured?

      biz.overages_disabled!
      assert biz.overages_disabled?
    end

    test "can be returned to no policy" do
      biz = create(:copilot_business)
      assert biz.overages_unconfigured?

      biz.overages_enabled!
      assert biz.overages_enabled?

      biz.overages_no_policy!
      assert biz.overages_no_policy?
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
      enable_feature_flag(:copilot_for_enterprise, business)
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
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns true if business has all required betas and direct managed enterprise copilot teams" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      enterprise_team = create(:enterprise_team, business: business)
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns true if business has all required betas and an IdP managed non-copilot enterprise team" do
      owner = create :emu, :owner
      business = owner.enterprise_managed_business
      copilot_business = Copilot::Business.new(business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      enterprise_team = create(:enterprise_team, business: business)
      external_group = create(:external_group, :with_members, :with_team, business: business, number_of_members: 2)
      EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)

      assert copilot_business.eligible_to_migrate_to_enterprise_teams?
    end if TestEnv.test_with_all_emus?

    test "returns false if business has all required betas and an IdP managed copilot team" do
      owner = create :emu, :owner
      business = owner.enterprise_managed_business
      copilot_business = Copilot::Business.new(business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      enterprise_team = create(:enterprise_team, business: business)
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)
      external_group = create(:external_group, :with_members, :with_team, business: business, number_of_members: 2)
      EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end if TestEnv.test_with_all_emus?

    test "returns false if enterprise_teams_migrate_from_cfg is disabled" do
      business = create(:business)
      copilot_business = Copilot::Business.new(business)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end

    test "returns false if business owns an org that cannot be deleted" do
      business = create(:business)
      create(:organization, business: business)
      Organization.any_instance.stubs(:permit_deletion?).returns(false)

      copilot_business = Copilot::Business.new(business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

      refute copilot_business.eligible_to_migrate_to_enterprise_teams?
    end
  end

  context "migrate_to_enterprise_teams" do
    test "doesn't work if enterprise_teams_migrate_from_cfg is disabled" do
      business = create(:business)
      disable_feature_flag(:enterprise_teams_migrate_from_cfb, business)
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
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)
      copilot_business = Copilot::Business.new(business)
      org = create(:organization, business: business)

      perform_enqueued_jobs(only: [UserDeleteJob]) do
        copilot_business.migrate_to_enterprise_teams
      end

      assert_nil Organization.find_by(id: org.id)
    end

    test "deletes organizations without migrating if seat_management_disabled" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)
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
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

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
      assert_equal org_1_enterprise_team, seat_assignments.first&.assignable
      assert_equal org_2_team_enterprise_team, seat_assignments.second&.assignable
      assert_equal org_2_direct_user_enterprise_team, seat_assignments.third&.assignable
    end

    test "calls copilot_org.migrate_to_enterprise_teams" do
      business = create(:business)
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)
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
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)

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
      enable_feature_flag(:enterprise_teams_migrate_from_cfb, business)
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

        perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
          copilot_biz.copilot_extensions_enabled!
        end

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

        perform_enqueued_jobs(only: [Copilot::BatchUpdateOrgSettingsJob]) do
          copilot_biz.copilot_extensions_disabled!
        end

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
        assert biz_config.dotcom_chat_enabled?
        assert biz_config.pr_summarizations_enabled?
        assert biz_config.github_enterprise_feature_group_enabled?
      end
    end
  end

  context "propagation to org" do
    test "#propagate_settings_for_org! - enable" do
      business = create(:business)
      org = create(:organization, business: business)
      biz_config = create(:copilot_configuration, :business, configurable: business)
      # public_code_suggestions does propagate but value is "allowed" not enabled
      keys_no_propagate = [:public_code_suggestions]
      policy_attributes = Copilot::Users::Policies::THE_POLICIES.collect { |policy| policy[:policy] } - keys_no_propagate

      policy_attributes.each do |attribute|
        biz_config.update!(attribute => "enabled")
      end

      org_config = create(:copilot_configuration, :organization, configurable: org)
      policy_attributes.each do |attribute|
        org_config.update!(attribute => "disabled")
      end

      copilot_biz = Copilot::Business.new(business)
      copilot_biz.propagate_settings_for_org!(Copilot::Organization.new(org))

      policy_attributes.each do |attribute|
        assert org_config.reload.public_send(attribute) == "enabled", "#{attribute} should be enabled"
      end
    end

    test "#propagate_settings_for_org! - disable" do
      business = create(:business)
      org = create(:organization, business: business)
      biz_config = create(:copilot_configuration, :business, configurable: business)
      # public_code_suggestions does propagate but value is "blocked" not disabled
      keys_no_propagate = [:public_code_suggestions]
      policy_attributes = Copilot::Users::Policies::THE_POLICIES.collect { |policy| policy[:policy] } - keys_no_propagate

      policy_attributes.each do |attribute|
        biz_config.update!(attribute => "disabled")
      end

      org_config = create(:copilot_configuration, :organization, configurable: org)
      policy_attributes.each do |attribute|
        org_config.update!(attribute => "enabled")
      end

      copilot_biz = Copilot::Business.new(business)
      copilot_biz.propagate_settings_for_org!(Copilot::Organization.new(org))

      policy_attributes.each do |attribute|
        assert org_config.reload.public_send(attribute) == "disabled", "#{attribute} should be disabled"
      end
    end

    test "#propagate_settings_for_org! - can disable sub policies while feature group is enabled" do
      business = create(:business)
      org = create(:organization, business: business)
      biz_config = create(:copilot_configuration, :business, configurable: business)
      sub_policies = %w[
        beta_features_github_chat
        user_feedback_opt_in
      ]

      biz_config.update!(github_enterprise_feature_group: "enabled")

      sub_policies.each do |attribute|
        biz_config.update!(attribute => "disabled")
      end

      org_config = create(:copilot_configuration, :organization, configurable: org)
      sub_policies.each do |attribute|
        org_config.update!(attribute => "enabled")
      end

      copilot_biz = Copilot::Business.new(business)
      copilot_biz.propagate_settings_for_org!(Copilot::Organization.new(org))

      sub_policies.each do |attribute|
        assert org_config.reload.public_send(attribute) == "disabled", "#{attribute} should be disabled"
      end
    end
  end
end if GitHub.copilot_enabled?
