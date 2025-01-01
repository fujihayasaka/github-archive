# typed: true
# frozen_string_literal: true

require "test_helper"

class ExternalConditionalAccessPolicyFilterTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @business = @emu.enterprise_managed_business
    @owner = @business.find_first_emu_owner
    @org = create(:organization, business: @business, admin: @emu)
  end

  setup do
    @filter = ConditionalAccess::Model::Filter::new(nil, actor: @emu, location: :test)
    @business.update_ip_allowlist_configuration(actor: @emu, config_value: "idp")
  end

  context "multiple applicable" do
    test "targets are not applicable when configurable is disabled" do
      @business.disable_idp_ip_allowlist_for_web(actor: @owner)
      refute_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end

    test "targets are applicable when configurable is enabled" do
      @business.enable_idp_ip_allowlist_for_web(actor: @owner)
      assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      inputs = [@emu, @org]
      GitHub.context.push(actor_ip: "1.2.3.4")
      assert_equal inputs, @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end
  end

  context "multiple satisfied" do
    test "targets are satisfied when configurable is disabled" do
      # this is a weird test since satisfied will not be called
      # since applicable would have returned false when the configurable was disabled
      # but it's here to ensure that the feature flag is actually being checked
      @business.disable_idp_ip_allowlist_for_web(actor: @owner)
      refute_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      OIDC::CapValidator.stubs(:satisfies_idp_cap?).returns(:yes)

      inputs = [@emu, @org]
      result = {
        @emu => { private: :satisfied },
        @org => { private: :satisfied }
      }
      assert_equal result, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end

    test "targets are satisfied when configurable is enabled and AAD CAP is success" do
      @business.enable_idp_ip_allowlist_for_web(actor: @owner)
      assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      OIDC::CapValidator.stubs(:satisfies_idp_web_cap?).returns(:yes)

      inputs = [@emu, @org]
      result = {
        @emu => { private: :satisfied },
        @org => { private: :satisfied }
      }
      assert_equal result, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end

    test "targets are not satisfied when configurable is enabled and AAD CAP is failure" do
      @business.enable_idp_ip_allowlist_for_web(actor: @owner)
      assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

      OIDC::CapValidator.stubs(:satisfies_idp_web_cap?).returns(:no)
      inputs = [@emu, @org]
      result = {
        @emu => { private: :unsatisfied },
        @org => { private: :unsatisfied }
      }
      assert_equal result, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end
  end
end
