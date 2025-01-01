# typed: true
# frozen_string_literal: true

require "test_helper"

class Business::ResourcesTest < GitHub::TestCase
  test "PUBLIC_SUBJECT_TYPES" do
    expected_public_subject_types = []
    assert_same_elements expected_public_subject_types, Business::Resources::PUBLIC_SUBJECT_TYPES
  end

  test "PRIVATE_SUBJECT_TYPES" do
    expected_private_subject_types = %w[
      enterprise_vulnerabilities
      enterprise_administration
      test_subject_for_required_permissions
    ]
    assert_same_elements expected_private_subject_types, Business::Resources::PRIVATE_SUBJECT_TYPES
  end

  test "PREVIEW_SUBJECTS_AND_FEATURE_FLAGS" do
    expected_preview_subjects = {
      "enterprise_organization_installations" => :enterprise_app_installation_management,
      "enterprise_organization_installation_repositories" => :enterprise_app_installation_management,
      "enterprise_custom_properties" => :enterprise_custom_properties_fgp,
    }

    assert_equal expected_preview_subjects, Business::Resources::PREVIEW_SUBJECTS_AND_FEATURE_FLAGS
  end

  test "ENTERPRISE_SUBJECT_TYPES" do
    expected_enterprise_subject_types = [
      "user_provisioning",
    ]
    assert_same_elements expected_enterprise_subject_types, Business::Resources::ENTERPRISE_SUBJECT_TYPES
  end

  test "ABILITY_TYPE_PREFIX" do
    assert_equal "Business", Business::Resources::ABILITY_TYPE_PREFIX
  end

  test "#business returns the parent Business" do
    biz = Business.new
    assert_equal biz, biz.resources.business
  end

  test "individual resources should be of type 'IntegrationInstallation::AbilityCollection'" do
    biz = Business.new
    assert biz.resources.enterprise_administration.is_a?(IntegrationInstallation::AbilityCollection), "should be of type 'IntegrationInstallation::AbilityCollection'"
  end
end
