# typed: true
# frozen_string_literal: true

require "test_helper"

class Organization::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = %w(
      members
      organization_user_blocking
      organization_projects
      team_discussions
      organization_actions_variables
      organization_administration
      organization_announcement_banners
      organization_codespaces
      organization_codespaces_secrets
      organization_codespaces_settings
      organization_copilot_seat_management
      organization_custom_org_roles
      organization_custom_properties
      organization_custom_roles
      organization_dependabot_secrets
      organization_events
      organization_hooks
      organization_plan
      organization_secrets
      organization_self_hosted_runners
      organization_personal_access_tokens
      organization_personal_access_token_requests
    )

    assert_same_elements expected_public_subject_types, Organization::Resources::PUBLIC_SUBJECT_TYPES

    organization = Organization.new
    expected_public_subject_types.each do |st|
      assert organization.resources.respond_to?(st.to_sym), "organization resources should include #{st}"
    end
  end

  test "PRIVATE_SUBJECT_TYPES" do
    expected_private_subject_types = %w(
      enterprise_vulnerabilities
      organization_packages
    )

    assert_equal expected_private_subject_types, Organization::Resources::PRIVATE_SUBJECT_TYPES
  end

  test "PREVIEW_SUBJECTS_AND_FEATURE_FLAGS" do
    expected_preview_subjects = {
      "issue_types" => :issue_types,
      "organization_api_insights" => :api_insights,
      "organization_campaigns" => :campaigns_api,
      "organization_network_configurations" => :actions_network_configuration_api,
      "organization_runner_custom_images" => :larger_runners_custom_image_generation,
      "organization_knowledge_bases" => :copilot_org_knowledge_bases_api,
      "organization_private_registries" => :private_registry_config_api
    }

    assert_same_hash expected_preview_subjects, Organization::Resources::PREVIEW_SUBJECTS_AND_FEATURE_FLAGS
  end

  test "ENTERPRISE_SUBJECT_TYPES" do
    enterprise_subject_types = %w(organization_pre_receive_hooks)
    assert_equal enterprise_subject_types, Organization::Resources::ENTERPRISE_SUBJECT_TYPES
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "Organization", Organization::Resources::ABILITY_TYPE_PREFIX
  end

  test "READONLY_SUBJECT_TYPES" do
    expected_readonly_subject_types = %w(
      organization_api_insights
      organization_events
      organization_plan
    )

    assert_same_elements expected_readonly_subject_types, Organization::Resources::READONLY_SUBJECT_TYPES

    organization = Organization.new
    expected_readonly_subject_types.each do |st|
      assert organization.resources.respond_to?(st.to_sym), "organization resources should include #{st}"
    end
  end

  test "ADMINABLE_SUBJECT_TYPES" do
    expected_adminable_subject_types = %w(
      organization_custom_properties
      organization_projects
    )

    assert_same_elements expected_adminable_subject_types, Organization::Resources::ADMINABLE_SUBJECT_TYPES

    organization = Organization.new
    expected_adminable_subject_types.each do |st|
      assert organization.resources.respond_to?(st.to_sym), "organization resources should include #{st}"
    end
  end

  test "EXCLUDED_SUBJECT_TYPES_FOR_TYPE" do
    expected_excluded_types_for_type = {
      UserProgrammaticAccess => %w(organization_personal_access_token_requests organization_personal_access_tokens),
    }

    assert_same_hash expected_excluded_types_for_type, Organization::Resources::EXCLUDED_SUBJECT_TYPES_FOR_TYPE
  end

  test "public subject types are not in preview, private or enterprise subject types" do
    Organization::Resources::PUBLIC_SUBJECT_TYPES.each do |subject|
      refute_includes Organization::Resources::PREVIEW_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and feature-flagged subject types"
      refute_includes Organization::Resources::PRIVATE_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and private subject types"
      refute_includes Organization::Resources::ENTERPRISE_SUBJECT_TYPES, subject, "#{subject} cannot be included in both public and enterprise subject types"
    end
  end

  test "#organization returns the parent Organization" do
    organization = Organization.new
    assert_equal organization, organization.resources.organization
  end

  test "individual resources should be of type 'IntegrationInstallation::AbilityCollection'" do
    organization = Organization.new
    assert organization.resources.members.is_a?(IntegrationInstallation::AbilityCollection), "should be of type 'IntegrationInstallation::AbilityCollection'"
  end
end
