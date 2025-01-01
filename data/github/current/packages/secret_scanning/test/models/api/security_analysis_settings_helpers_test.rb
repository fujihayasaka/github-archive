# typed: true
# frozen_string_literal: true

require "test_helper"

class Api::App::SecurityAnalysisSettingsHelpersTest < Api::TestCase
  include Api::App::SecurityAnalysisSettingsHelpers
  include Api::App::HelpersDependency
  include SecurityAnalysisSettingsHelper
  include ApiIntegrationHelpers

  fixtures do
    @owner = create :user, login: "owner", plan: "medium"
    @org = create :organization
    @repo = create(:repository, owner: @org, name: "server")
  end

  def current_user
    @owner
  end

  context "update_tenant_security_and_analysis_configuration" do
    test "maps booleans without enablement changeset" do
      source_params = { "secret_scanning_enabled_for_new_repositories" => "true", "secret_scanning_push_protection_enabled_for_new_repositories" => "false" }
      expected_mapped_params = { "secret_scanning_new_repos" => "enabled",
        "secret_scanning_push_protection_new_repos" => "disabled" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: false)
    end

    test "maps booleans with enablement changeset" do
      source_params = { "secret_scanning_enabled_for_new_repositories" => "true", "secret_scanning_push_protection_enabled_for_new_repositories" => "false" }
      expected_mapped_params = { "secret_scanning_new_repos" => "enabled",
        "secret_scanning_push_protection_new_repos" => "disabled" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: true)
    end

    test "takes no action if url provided without enabled flag without changeset" do
      source_params = { "secret_scanning_push_protection_custom_link" => "example-link" }

      UpdateSecuritySettings.expects(:new).never
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: false)
    end

    test "maps both link and enabled (when true) without changeset" do
      source_params = { "secret_scanning_push_protection_custom_link_enabled" => "true", "secret_scanning_push_protection_custom_link" => "example-link" }
      expected_mapped_params = { "push_protection_custom_message_status" => "enabled",
        "push_protection_custom_message" => "example-link" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: false)
    end

    test "maps enabled (when true) when missing link without changeset" do
      source_params = { "secret_scanning_push_protection_custom_link_enabled" => "true" }
      expected_mapped_params = { "push_protection_custom_message_status" => "enabled",
        "push_protection_custom_message" => nil }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: false)
    end

    test "maps enabled (when false) without changeset" do
      source_params = { "secret_scanning_push_protection_custom_link_enabled" => "false", "secret_scanning_push_protection_custom_link" => "useless-link" }
      expected_mapped_params = { "push_protection_custom_message_status" => "disabled" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: false)
    end

    test "maps both link and enabled when link provided with changeset" do
      source_params = { "secret_scanning_push_protection_custom_link" => "example-link" }
      expected_mapped_params = { "push_protection_custom_message_status" => "enabled",
        "push_protection_custom_message" => "example-link" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: true)
    end

    test "maps both link and disabled when null link provided with changeset" do
      source_params = { "secret_scanning_push_protection_custom_link" => nil }
      expected_mapped_params = { "push_protection_custom_message_status" => "disabled" }

      demo_instance = {}
      UpdateSecuritySettings.expects(:new).with(@org, expected_mapped_params, actor: @owner, blocked_settings: nil, source: "rest-api").returns(demo_instance)
      demo_instance.expects(:perform)
      update_tenant_security_and_analysis_configuration(@org, settings: source_params, should_remove_custom_link_enablement_field: true)
    end
  end
end
