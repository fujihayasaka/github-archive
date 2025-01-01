# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Instrumentation::EntitySerializerTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @product_uuid_subscribable ||= create(:billing_product_uuid, :copilot)
    @yearly_product_uuid_subscribable = create(:billing_product_uuid, :copilot, billing_cycle: :year)
  end

  context "entity Hydro::EntitySerializer" do
    context "copilot_telemetry_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_telemetry_setting(:SPAGHETTI)
      end

      test "defaults to enabled" do
        user = create(:user)
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, configurable: user)

        assert_equal :ENABLED, Hydro::EntitySerializer.copilot_telemetry_setting(
          copilot_user.telemetry_enabled?
        )
      end

      test "enable it" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)
        copilot_user.enable_telemetry!

        assert_equal :ENABLED, Hydro::EntitySerializer.copilot_telemetry_setting(
          copilot_user.telemetry_enabled?
        )
      end

      test "disable it" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.disable_telemetry!

        assert_equal :DISABLED, Hydro::EntitySerializer.copilot_telemetry_setting(
          copilot_user.telemetry_enabled?
        )
      end

      test "cfb seat defaults to disabled" do
        seat = create(:copilot_seat)
        user = seat.assigned_user
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, configurable: user)

        assert_equal :DISABLED, Hydro::EntitySerializer.copilot_telemetry_setting(
          copilot_user.telemetry_enabled?
        )
      end

      test "cfb seat defaults to enabled for magical orgs" do
        ::User.any_instance.stubs(:organization_ids).returns([Copilot::GITHUB_ORG_ID])
        seat = create(:copilot_seat)
        user = seat.assigned_user
        copilot_user = Copilot::User.new(user)
        create(:copilot_configuration, :user, configurable: user)

        assert_equal :ENABLED, Hydro::EntitySerializer.copilot_telemetry_setting(
          copilot_user.telemetry_enabled?
        )
      end
    end

    context "copilot_snippy_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_snippy_setting(:SPAGHETTI)
      end

      test "do nothing (user)" do
        user = create(:user)
        configuration = create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        refute copilot_user.public_code_suggestions_configured?
        assert configuration.public_code_suggestions_unconfigured?

        assert_equal :SNIPPY_UNCONFIGURED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_user.copilot_snippy_setting,
        )
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_business.public_code_suggestions_configured?
        refute copilot_org.public_code_suggestions_configured?

        assert_equal :SNIPPY_NO_POLICY, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_business.copilot_snippy_setting,
        )
        assert_equal :SNIPPY_UNCONFIGURED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.public_code_suggestions_configured?

        assert_equal :SNIPPY_UNCONFIGURED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end

      test "enable it (user)" do
        user = create(:user)
        configuration = create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        refute copilot_user.public_code_suggestions_configured?
        assert configuration.public_code_suggestions_unconfigured?

        copilot_user.block_public_code_suggestions!

        assert_equal :SNIPPY_ENABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_user.copilot_snippy_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_business.public_code_suggestions_configured?
        copilot_business.block_public_code_suggestions!

        assert_equal :SNIPPY_ENABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_business.copilot_snippy_setting,
        )
        assert_equal :SNIPPY_ENABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.public_code_suggestions_configured?
        copilot_org.block_public_code_suggestions!

        assert_equal :SNIPPY_ENABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end

      test "disable it (user)" do
        user = create(:user)
        configuration = create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        refute copilot_user.public_code_suggestions_configured?
        assert configuration.public_code_suggestions_unconfigured?

        copilot_user.allow_public_code_suggestions!

        assert_equal :SNIPPY_DISABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_user.copilot_snippy_setting
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_business.public_code_suggestions_configured?
        copilot_business.allow_public_code_suggestions!

        assert_equal :SNIPPY_DISABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_business.copilot_snippy_setting,
        )

        assert_equal :SNIPPY_DISABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.public_code_suggestions_configured?
        copilot_org.allow_public_code_suggestions!

        assert_equal :SNIPPY_DISABLED, Hydro::EntitySerializer.copilot_snippy_setting(
          copilot_org.copilot_snippy_setting,
        )
      end
    end

    context "copilot_editor_chat_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_editor_chat_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_business.chat_enabled_configured?

        assert_equal :EDITOR_CHAT_NO_POLICY, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_business.chat_setting,
        )

        assert_equal :EDITOR_CHAT_UNCONFIGURED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.chat_enabled_configured?

        assert_equal :EDITOR_CHAT_UNCONFIGURED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)


        assert_equal :EDITOR_CHAT_DISABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_user.chat_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert business.chat_enabled_configured?

        business.enable_chat!

        assert_equal :EDITOR_CHAT_ENABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          business.chat_setting,
        )

        assert_equal :EDITOR_CHAT_ENABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.chat_enabled_configured?

        copilot_org.enable_chat!

        assert_equal :EDITOR_CHAT_ENABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert business.chat_enabled_configured?

        business.disable_chat!

        assert_equal :EDITOR_CHAT_DISABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          business.chat_setting,
        )

        assert_equal :EDITOR_CHAT_DISABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.chat_enabled_configured?

        copilot_org.disable_chat!

        assert_equal :EDITOR_CHAT_DISABLED, Hydro::EntitySerializer.copilot_editor_chat_setting(
          copilot_org.chat_setting,
        )
      end
    end

    context "copilot_pr_summarizations_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_pr_summarizations_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.pr_summarizations_configured?

        assert_equal :PR_SUMMARIZATIONS_UNCONFIGURED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          business.pr_summarizations_setting,
        )

        assert_equal :PR_SUMMARIZATIONS_UNCONFIGURED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.pr_summarizations_configured?

        assert_equal :PR_SUMMARIZATIONS_UNCONFIGURED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert_equal :PR_SUMMARIZATIONS_UNCONFIGURED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_user.pr_summarizations_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.pr_summarizations_configured?

        business.pr_summarizations_enabled!

        assert_equal :PR_SUMMARIZATIONS_ENABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          business.pr_summarizations_setting,
        )

        assert_equal :PR_SUMMARIZATIONS_ENABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.pr_summarizations_configured?

        copilot_org.pr_summarizations_enabled!

        assert_equal :PR_SUMMARIZATIONS_ENABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "enable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.pr_summarizations_enabled!

        assert_equal :PR_SUMMARIZATIONS_ENABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_user.pr_summarizations_setting,
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.pr_summarizations_configured?

        business.pr_summarizations_disabled!

        assert_equal :PR_SUMMARIZATIONS_DISABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          business.pr_summarizations_setting,
        )
        assert_equal :PR_SUMMARIZATIONS_DISABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.pr_summarizations_configured?

        copilot_org.pr_summarizations_disabled!

        assert_equal :PR_SUMMARIZATIONS_DISABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_org.pr_summarizations_setting,
        )
      end

      test "disable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.pr_summarizations_disabled!

        assert_equal :PR_SUMMARIZATIONS_DISABLED, Hydro::EntitySerializer.copilot_pr_summarizations_setting(
          copilot_user.pr_summarizations_setting,
        )
      end
    end

    context "copilot_custom_models_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_custom_models_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.custom_models_configured?

        assert_equal :CUSTOM_MODELS_UNCONFIGURED, Hydro::EntitySerializer.copilot_custom_models_setting(
          business.custom_models_setting,
        )

        assert_equal :CUSTOM_MODELS_UNCONFIGURED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.custom_models_configured?

        assert_equal :CUSTOM_MODELS_UNCONFIGURED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert_equal :CUSTOM_MODELS_UNCONFIGURED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_user.custom_models_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.custom_models_configured?

        business.custom_models_enabled!

        assert_equal :CUSTOM_MODELS_ENABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          business.custom_models_setting,
        )

        assert_equal :CUSTOM_MODELS_ENABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.custom_models_configured?

        copilot_org.custom_models_enabled!

        assert_equal :CUSTOM_MODELS_ENABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "enable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.custom_models_enabled!

        assert_equal :CUSTOM_MODELS_ENABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_user.custom_models_setting,
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.custom_models_configured?

        business.custom_models_disabled!

        assert_equal :CUSTOM_MODELS_DISABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          business.custom_models_setting,
        )

        assert_equal :CUSTOM_MODELS_DISABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.custom_models_configured?

        copilot_org.custom_models_disabled!

        assert_equal :CUSTOM_MODELS_DISABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_org.custom_models_setting,
        )
      end

      test "disable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.custom_models_disabled!

        assert_equal :CUSTOM_MODELS_DISABLED, Hydro::EntitySerializer.copilot_custom_models_setting(
          copilot_user.custom_models_setting,
        )
      end
    end

    context "copilot_cli_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_cli_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.cli_configured?

        assert_equal :CLI_UNCONFIGURED, Hydro::EntitySerializer.copilot_cli_setting(
          business.cli_setting,
        )
        assert_equal :CLI_UNCONFIGURED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.cli_configured?

        assert_equal :CLI_UNCONFIGURED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert_equal :CLI_UNCONFIGURED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_user.cli_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.cli_configured?

        business.cli_enabled!

        assert_equal :CLI_ENABLED, Hydro::EntitySerializer.copilot_cli_setting(
          business.cli_setting,
        )
        assert_equal :CLI_ENABLED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.cli_configured?

        copilot_org.cli_enabled!

        assert_equal :CLI_ENABLED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.cli_configured?

        business.cli_disabled!

        assert_equal :CLI_DISABLED, Hydro::EntitySerializer.copilot_cli_setting(
          business.cli_setting,
        )
        assert_equal :CLI_DISABLED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.cli_configured?

        copilot_org.cli_disabled!

        assert_equal :CLI_DISABLED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_org.cli_setting,
        )
      end

      test "disable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.cli_disabled!

        assert_equal :CLI_DISABLED, Hydro::EntitySerializer.copilot_cli_setting(
          copilot_user.cli_setting,
        )
      end
    end

    context "copilot_private_docs_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_private_docs_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.private_docs_configured?

        assert_equal :PRIVATE_DOCS_UNCONFIGURED, Hydro::EntitySerializer.copilot_private_docs_setting(
          business.private_docs_setting,
        )
        assert_equal :PRIVATE_DOCS_UNCONFIGURED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.private_docs_configured?

        assert_equal :PRIVATE_DOCS_UNCONFIGURED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert_equal :PRIVATE_DOCS_UNCONFIGURED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_user.private_docs_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.private_docs_configured?

        business.private_docs_enabled!

        assert_equal :PRIVATE_DOCS_ENABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          business.private_docs_setting,
        )
        assert_equal :PRIVATE_DOCS_ENABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.private_docs_configured?

        copilot_org.private_docs_enabled!

        assert_equal :PRIVATE_DOCS_ENABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "enable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.private_docs_enabled!

        assert_equal :PRIVATE_DOCS_ENABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_user.private_docs_setting,
        )
      end

      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.private_docs_configured?

        business.private_docs_disabled!

        assert_equal :PRIVATE_DOCS_DISABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          business.private_docs_setting,
        )
        assert_equal :PRIVATE_DOCS_DISABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.private_docs_configured?

        copilot_org.private_docs_disabled!

        assert_equal :PRIVATE_DOCS_DISABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_org.private_docs_setting,
        )
      end

      test "disable it (user)" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        copilot_user.private_docs_disabled!

        assert_equal :PRIVATE_DOCS_DISABLED, Hydro::EntitySerializer.copilot_private_docs_setting(
          copilot_user.private_docs_setting,
        )
      end
    end

    context "copilot_github_chat_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_github_chat_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.dotcom_chat_configured?

        assert_equal :GITHUB_CHAT_UNCONFIGURED, Hydro::EntitySerializer.copilot_github_chat_setting(
          business.dotcom_chat_setting,
        )
        assert_equal :GITHUB_CHAT_UNCONFIGURED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.dotcom_chat_configured?

        assert_equal :GITHUB_CHAT_UNCONFIGURED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, :user, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert copilot_user.dotcom_chat_configured?

        assert_equal :GITHUB_CHAT_DISABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_user.dotcom_chat_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.dotcom_chat_configured?

        business.dotcom_chat_enabled!

        assert_equal :GITHUB_CHAT_ENABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          business.dotcom_chat_setting,
        )
        assert_equal :GITHUB_CHAT_ENABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.dotcom_chat_configured?

        copilot_org.dotcom_chat_enabled!

        assert_equal :GITHUB_CHAT_ENABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end


      test "disable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        refute business.dotcom_chat_configured?

        business.disable_dotcom_chat!

        assert_equal :GITHUB_CHAT_DISABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          business.dotcom_chat_setting,
        )
        assert_equal :GITHUB_CHAT_DISABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end

      test "disable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        refute copilot_org.dotcom_chat_configured?

        copilot_org.disable_dotcom_chat!

        assert_equal :GITHUB_CHAT_DISABLED, Hydro::EntitySerializer.copilot_github_chat_setting(
          copilot_org.dotcom_chat_setting,
        )
      end
    end

    context "copilot_mobile_chat_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_mobile_chat_setting(:SPAGHETTI)
      end

      test "do nothing (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert business.mobile_chat_disabled?

        assert_equal :MOBILE_CHAT_DISABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          business.mobile_chat_setting,
        )
        assert_equal :MOBILE_CHAT_DISABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          copilot_org.mobile_chat_setting,
        )
      end

      test "do nothing (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_org.mobile_chat_disabled?

        assert_equal :MOBILE_CHAT_DISABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          copilot_org.mobile_chat_setting,
        )
      end

      test "do nothing (user)" do
        user = create(:user)
        create(:copilot_configuration, :user, configurable: user)
        copilot_user = Copilot::User.new(user)

        assert copilot_user.mobile_chat_disabled?

        assert_equal :MOBILE_CHAT_DISABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          copilot_user.mobile_chat_setting,
        )
      end

      test "enable it (business)" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)
        copilot_org = Copilot::Organization.new(organization)

        assert business.mobile_chat_disabled?

        business.enable_mobile_chat!

        assert_equal :MOBILE_CHAT_ENABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          business.mobile_chat_setting,
        )
        assert_equal :MOBILE_CHAT_ENABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          copilot_org.mobile_chat_setting,
        )
      end

      test "enable it (organization)" do
        organization = create(:copilot_for_business_enabled_organization)
        copilot_org = Copilot::Organization.new(organization)

        assert copilot_org.mobile_chat_disabled?

        copilot_org.enable_mobile_chat!

        assert_equal :MOBILE_CHAT_ENABLED, Hydro::EntitySerializer.copilot_mobile_chat_setting(
          copilot_org.mobile_chat_setting,
        )
      end
    end

    context "copilot_enabled_setting" do
      test "symbol" do
        assert_equal :SPAGHETTI, Hydro::EntitySerializer.copilot_enabled_setting(:SPAGHETTI)
      end

      test "converts to symbol" do
        assert_equal :COPILOT_ENABLED, Hydro::EntitySerializer.copilot_enabled_setting("enabled")
        assert_equal :COPILOT_DISABLED, Hydro::EntitySerializer.copilot_enabled_setting("disabled")
        assert_equal :COPILOT_ALL_ORGANIZATIONS, Hydro::EntitySerializer.copilot_enabled_setting("all_organizations")
        assert_equal :COPILOT_SELECTED_ORGANIZATIONS, Hydro::EntitySerializer.copilot_enabled_setting("selected_organizations")
      end
    end

    context "copilot_subscription_plan" do
      test "empty plan" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(nil), :UNKNOWN_PLAN
      end

      test "year symbol plan" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(:year), :YEARLY
      end

      test "yearly symbol plan" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(:yearly), :YEARLY
      end

      test "month symbol plan" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(:month), :MONTHLY
      end

      test "monthly symbol plan" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(:monthly), :MONTHLY
      end

      test "literally any other value" do
        assert_equal Hydro::EntitySerializer.copilot_subscription_plan(:potato), :NO_SUBSCRIPTION
      end
    end

    context "copilot_free_user_type" do
      test "it is never unknown" do
        Copilot::FreeUser::FREE_USER_TYPES.each do |type|
          refute_equal :FREE_USER_UNKNOWN,
            Hydro::EntitySerializer.copilot_free_user_type(type.name),
            "Failed for #{type.name}"
        end
      end

      test "correctly maps Complimentary Access" do
        assert_equal :COMPLIMENTARY_ACCESS,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::COMPLIMENTARY_ACCESS.name)
      end

      test "correctly maps Educational" do
        assert_equal :EDUCATIONAL,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::EDUCATIONAL.name)
      end

      test "correctly maps EngagedOSS" do
        assert_equal :ENGAGED_OSS,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::ENGAGED_OSS.name)
      end

      test "correctly maps Faculty" do
        assert_equal :FACULTY,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::FACULTY.name)
      end

      test "correctly maps GitHub Star" do
        assert_equal :GITHUB_STAR,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::GITHUB_STAR.name)
      end

      test "correctly maps Hey GitHub" do
        assert_equal :HEY_GITHUB,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::HEY_GITHUB.name)
      end

      test "correctly maps MS MVP" do
        assert_equal :MS_MVP,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::MS_MVP.name)
      end

      test "correctly maps WORKSHOP" do
        assert_equal :WORKSHOP,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::WORKSHOP.name)
      end

      test "correctly maps Technical Preview Extension" do
        assert_equal :TECHNICAL_PREVIEW_EXTENSION,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::TECHNICAL_PREVIEW_EXTENSION.name)
      end

      test "correctly maps Y Combinator" do
        assert_equal :Y_COMBINATOR,
          Hydro::EntitySerializer.copilot_free_user_type(Copilot::FreeUser::Y_COMBINATOR.name)
      end
    end

    context "copilot_owner_details" do
      test "it loads the organization" do
        organization = create(:copilot_for_business_enabled_organization)
        result = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_includes result, :organization
        assert_equal organization.id, result[:organization][:id]
        assert_includes result, :business

        organization = create(:copilot_feature_enabled_enterprise_organization)
        result = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_includes result, :organization
        assert_equal organization.id, result[:organization][:id]
        assert_nil result[:business]
      end

      test "handles credit card organization" do
        organization = create(:credit_card_organization)
        refute_nil organization.customer
        organization.customer.update(billing_type: ::Customer::BILLING_TYPE_CARD)
        details = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_equal "card", details[:billing_type], "Credit card organization expected to be 'card'"
      end

      test "handles credit card organization without customer update" do
        organization = create(:credit_card_organization)
        refute_nil organization.customer
        details = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_equal "card", details[:billing_type], "Credit card organization expected to be 'card'"
      end

      test "handles paypal_organizationn" do
        organization = create(:paypal_org)
        refute_nil organization.customer
        organization.customer.update(billing_type: "paypal")
        details = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_equal "paypal", details[:billing_type]
      end

      test "handles invoiced" do
        organization = create(:invoiced_organization)
        details = Hydro::EntitySerializer.copilot_owner_details(organization)
        assert_equal "invoice", details[:billing_type]
      end
    end

    context "copilot_seat" do
      test "it loads the seat" do
        seat = create(:copilot_seat)
        result = Hydro::EntitySerializer.copilot_seat(seat)
        assert_equal seat.assigned_user.id, result[:assigned_user][:id]
        assert_equal Google::Protobuf::Timestamp.new(seconds: seat.created_at.to_i, nanos: 0), result[:created_at]
        refute result[:enterprise_id]
        assert_equal seat.id, result[:id]
        assert_equal seat.seat_assignment.owner_id, result[:organization_id]
        assert_equal seat.seat_assignment.assignable_id, result[:assignment][:assignable_id]
      end
    end

    context "copilot_seat_emission" do
      test "it loads the seat emission" do
        emission = create(:copilot_seat_emission)
        result = Hydro::EntitySerializer.copilot_seat_emission(emission)
        assert_equal emission.id, result[:id]
        assert_equal emission.owner.id, result[:organization][:id]
        assert_equal emission.unique_id, result[:unique_id]
        refute result[:business]

        # in a future pr, seat emissions will use only their owner, but not yet, so we have to hack this
        business = create(:business)
        emission.update_columns(owner_id: business.id, owner_type: "Business")

        result = Hydro::EntitySerializer.copilot_seat_emission(emission)
        assert_equal emission.id, result[:id]
        assert_equal emission.owner.id, result[:business][:id]
        assert_equal emission.unique_id, result[:unique_id]
      end
    end

    context "copilot_seat_assignment" do
      test "it loads the seat assignment" do
        seat_assignment = create(:copilot_seat_assignment, :team)
        result = Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment)
        assert_equal seat_assignment.id, result[:id]
        assert_equal seat_assignment.owner.id, result[:organization][:id]
        assert_equal "Team", result[:assignable_type]
        assert_equal seat_assignment.assignable.id, result[:assignable_id]

        seat_assignment.unassign!(seat_assignment.organization.admins.first)

        result = Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment)
        assert_equal seat_assignment.id, result[:id]
        assert_equal seat_assignment.owner.id, result[:organization][:id]
        assert_equal "Team", result[:assignable_type]
        assert_equal seat_assignment.assignable.id, result[:assignable_id]

        proto_pending_cancellation_date = Google::Protobuf::Timestamp.new(seconds: seat_assignment.pending_cancellation_date.to_time.to_i, nanos: 0)
        assert_equal proto_pending_cancellation_date, result[:pending_cancellation_date]

        # in a future pr, seat emissions will use only their owner, but not yet, so we have to hack this
        business = create(:business)
        seat_assignment.update_columns(owner_id: business.id, owner_type: "Business")

        result = Hydro::EntitySerializer.copilot_seat_assignment(seat_assignment)
        assert_equal seat_assignment.id, result[:id]
        assert_equal seat_assignment.owner.id, result[:business][:id]
        assert_equal "Team", result[:assignable_type]

      end
    end

    context "copilot_for_business_details" do
      test "it loads the details" do
        details = {
          apple: "banana",
          orange: "pear",
        }
        result = Hydro::EntitySerializer.copilot_for_business_details(details)

        expected = [
          {
            key: "apple",
            value: "banana",
          },
          {
            key: "orange",
            value: "pear",
          },
        ]
        assert_equal expected, result
      end
    end

    context "copilot_business_settings" do
      test "it loads the settings" do
        organization = create(:copilot_for_business_enabled_organization)
        business = Copilot::Business.new(organization.business)

        result = Hydro::EntitySerializer.copilot_business_settings(business.copilot_business_settings)

        assert_equal business.copilot_business_settings[:snippy_setting], result[:snippy_setting]
        assert_equal business.copilot_business_settings[:copilot_enabled_setting], result[:copilot_enabled_setting]
        assert_equal business.copilot_business_settings[:editor_chat_setting], result[:editor_chat_setting]
        assert_equal business.copilot_business_settings[:mobile_chat_setting], result[:mobile_chat_setting]
        assert_equal business.copilot_business_settings[:github_chat_setting], result[:github_chat_setting]
        assert_equal business.copilot_business_settings[:cli_setting], result[:cli_setting]
        assert_equal business.copilot_business_settings[:pr_summarizations_setting], result[:pr_summarizations_setting]
        assert_equal business.copilot_business_settings[:private_docs_setting], result[:private_docs_setting]
        assert_equal business.copilot_business_settings[:usage_telemetry_api_setting], result[:usage_telemetry_api_setting]
      end
    end

    context "copilot_organization_settings" do
      test "it loads the settings" do
        org = create(:copilot_for_business_enabled_organization)
        organization = Copilot::Organization.new(org)
        result = Hydro::EntitySerializer.copilot_organization_settings(organization.copilot_organization_settings)

        assert_equal organization.copilot_organization_settings[:snippy_setting], result[:snippy_setting]
        assert_equal organization.copilot_organization_settings[:copilot_enabled_setting], result[:copilot_enabled_setting]
        assert_equal organization.copilot_organization_settings[:editor_chat_setting], result[:editor_chat_setting]
        assert_equal organization.copilot_organization_settings[:github_chat_setting], result[:github_chat_setting]
        assert_equal organization.copilot_organization_settings[:cli_setting], result[:cli_setting]
        assert_equal organization.copilot_organization_settings[:pr_summarizations_setting], result[:pr_summarizations_setting]
        assert_equal organization.copilot_organization_settings[:private_docs_setting], result[:private_docs_setting]
        assert_equal organization.copilot_organization_settings[:usage_telemetry_api_setting], result[:usage_telemetry_api_setting]
      end
    end

    context "copilot_settings" do
      test "it loads the settings" do
        user = create(:user)
        create(:copilot_configuration, configurable: user)
        copilot_user = Copilot::User.new(user)

        result = Hydro::EntitySerializer.copilot_organization_settings(copilot_user.copilot_user_settings)

        assert_equal copilot_user.copilot_user_settings[:snippy_setting], result[:snippy_setting]
        assert_equal copilot_user.copilot_user_settings[:editor_chat_setting], result[:editor_chat_setting]
        assert_equal copilot_user.copilot_user_settings[:github_chat_setting], result[:github_chat_setting]
        assert_equal copilot_user.copilot_user_settings[:cli_setting], result[:cli_setting]
        assert_equal copilot_user.copilot_user_settings[:pr_summarizations_setting], result[:pr_summarizations_setting]
        assert_equal copilot_user.copilot_user_settings[:private_docs_setting], result[:private_docs_setting]
      end
    end
  end
end if GitHub.copilot_enabled?
