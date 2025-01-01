# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalConditionalAccessPolicyFilterTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @business = @emu.enterprise_managed_business
    @org = create(:organization, business: @business, admin: @owner)
  end

  setup do
    @filter = ConditionalAccess::Model::Filter::new(nil, actor: @emu, location: :test)
    GitHub.flipper[:idp_cap_for_filters].enable
    @business.update_ip_allowlist_configuration(actor: @emu, config_value: "idp")
  end

  context "multiple applicable" do
    test "targets are applicable when feature flag is enabled" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      inputs = [@emu, @org]
      assert_equal inputs, @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end

    test "targets are not applicable when feature flag is disabled" do
      GitHub.flipper[:idp_cap_for_web].disable
      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end
  end

  context "multiple satisfied" do
    test "targets are satisfied when feature flag is enabled and AAD CAP is successful" do
      OIDC::CapValidator.stubs(:satisfies_idp_web_cap?).returns(:yes)
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      inputs = [@emu, @org]
      assert_equal inputs, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end

    test "targets are not satisfied when feature flag is enabled and AAD CAP is failure" do
      OIDC::CapValidator.stubs(:satisfies_idp_web_cap?).returns(:no)
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end

    test "targets are not satisfied when feature flag is disabled" do
      # this is a bit of a weird test since satisfied will not be called
      # since appliacable would have returned false when feature flag is disabed
      # but it's here to ensure that the feature flag is actually being checked
      OIDC::CapValidator.stubs(:satisfies_idp_cap?).returns(:yes)
      GitHub.flipper[:idp_cap_for_web].disable
      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end
  end
end
