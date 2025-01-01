# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgRoleFgpsTest < GitHub::TestCase

  setup do
    @org = T.let(create(:organization, business: create(:business)), Organization)
    # Hash with FGP as the key, feature flag as the value
    @feature_flagged_fgps = {
      manage_organization_actions_self_hosted_runners: :actions_self_hosted_settings_fgp,
      write_organization_packages: :packages_org_write_fgp,
      read_organization_network_configurations: :actions_network_configuration_api,
      write_organization_network_configurations: :actions_network_configuration_api,
      read_organization_runner_custom_images: :larger_runners_custom_image_generation,
      write_organization_runner_custom_images: :larger_runners_custom_image_generation,
      org_review_and_manage_secret_scanning_bypass_requests: :display_org_review_manage_ss_bypass_requests_fgp,
      org_review_and_manage_secret_scanning_closure_requests: :display_org_review_and_manage_secret_scanning_closure_requests_fgp,
      org_bypass_secret_scanning_closure_requests: :display_org_bypass_secret_scanning_closure_requests_fgp,
      view_org_api_insights: :api_insights_org_viewer_fgp
    }
    @disabled_feature_flags = @feature_flagged_fgps.values.uniq
    @other_feature_flags_to_enable = [:actions_usage_metrics]
  end

  test "OrgRoleFgps.for takes an org" do
    fgps = OrgRoleFgps.for(owner: @org)

    assert fgps
  end

  test "OrgRoleFgps.available_fgps returns all available FGPs" do
    org_custom_role_fgps = Permissions::FineGrainedPermissionIm.org_fgps_for_custom_roles.map { |fgp| fgp.action.to_sym }

    # enable the feature flagged FGPS
    GitHub.stubs(:actions_enabled?).returns(true)
    GitHub.stubs(:oauth_application_policies_enabled?).returns(true)
    @disabled_feature_flags.each { |ff| GitHub.flipper[ff].enable }
    @other_feature_flags_to_enable.each { |ff| GitHub.flipper[ff].enable }

    fgps = OrgRoleFgps.for(owner: @org)

    # NOTE(assyadh): This were temporarily removed 3 years ago.
    disabled_fgps = [
      :manage_topics,
      :remove_label,
      :remove_assignee,
    ]

    custom_properties_fgps = []
    custom_properties_fgps += [:read_organization_actions_usage_metrics] unless @org.insights_enabled?

    assert_same_elements org_custom_role_fgps - disabled_fgps - custom_properties_fgps, fgps.available_fgps(@org).map(&:label)
    assert_same_elements org_custom_role_fgps - custom_properties_fgps, fgps.available_fgps(@org).map(&:label)
  end


  context "Feature Flagged OrgRoleFGPs" do
    test "are not included when FF is disabled" do
      @disabled_feature_flags.each { |ff| GitHub.flipper[ff].disable }
      enabled_fgps = OrgRoleFgps.custom_role_fgps(@org)
      @feature_flagged_fgps.keys.each do |fgp|
        refute_includes enabled_fgps, fgp
      end
    end

    test "are included when FF is enabled" do
      GitHub.stubs(:actions_enabled?).returns(true)
      @disabled_feature_flags.each { |ff| GitHub.flipper[ff].enable }
      @other_feature_flags_to_enable.each { |ff| GitHub.flipper[ff].enable }
      enabled_fgps = OrgRoleFgps.custom_role_fgps(@org)
      @feature_flagged_fgps.keys.each do |fgp|
        assert_includes enabled_fgps, fgp
      end
    end
  end
end
