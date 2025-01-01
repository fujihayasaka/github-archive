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
    GitHub.flipper[:idp_cap_for_filters].enable
    @business.update_ip_allowlist_configuration(actor: @emu, config_value: "idp")
  end

  context "multiple applicable" do
    test "targets are not applicable when only idp cap for web feature flag is enabled" do
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      GitHub.flipper[:idp_cap_web_configurable_allowed].disable
      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end

    test "targets are not applicable when feature flag is disabled" do
      GitHub.flipper[:idp_cap_for_web].disable
      inputs = [@emu, @org]
      assert_equal [], @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
    end

    context "idp_cap_web_configurable_allowed" do
      test "targets are not applicable when idp_cap_web_configurable_allowed but configurable is disabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)
        GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
        @business.disable_idp_ip_allowlist_for_web(actor: @owner)
        refute_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

        inputs = [@emu, @org]
        assert_equal [], @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
      end

      test "targets are applicable when idp_cap_web_configurable_allowed and configurable is enabled" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)
        GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
        @business.enable_idp_ip_allowlist_for_web(actor: @owner)
        assert_predicate @business, :idp_ip_allowlist_for_web_configurable_enabled?

        inputs = [@emu, @org]
        assert_equal inputs, @filter.multiple_external_conditional_access_policy_applicable(inputs, @filter.target_provider)
      end
    end
  end

  context "multiple satisfied" do
    test "targets are not satisfied when everything is enabled and AAD CAP is failure" do
      OIDC::CapValidator.stubs(:satisfies_idp_web_cap?).returns(:no)
      GitHub.flipper[:idp_cap_for_web].enable(@business)
      GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
      @business.enable_idp_ip_allowlist_for_web(actor: @owner)
      inputs = [@emu, @org]
      result = {
        @emu => { private: :unsatisfied },
        @org => { private: :unsatisfied }
      }
      assert_equal result, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end

    test "targets are satisfied when feature flag is disabled" do
      # this is a bit of a weird test since satisfied will not be called
      # since applicable would have returned false when feature flag is disabed
      # but it's here to ensure that the feature flag is actually being checked
      OIDC::CapValidator.stubs(:satisfies_idp_cap?).returns(:yes)
      GitHub.flipper[:idp_cap_for_web].disable
      inputs = [@emu, @org]
      result = {
        @emu => { private: :satisfied },
        @org => { private: :satisfied }
      }
      assert_equal result, @filter.multiple_external_conditional_access_policy_satisfied(inputs, @filter.target_provider)
    end


    context "idp_cap_web_configurable_allowed" do
      test "targets are satisfied when idp_cap_web_configurable_allowed but configurable is disabled" do
        # similar to above this is a weird test since satisfied will not be called
        # since applicable would have returned false when the configurable was disabled
        # but it's here to ensure that the feature flag is actually being checked
        GitHub.flipper[:idp_cap_for_web].enable(@business)
        GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
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

      test "targets are satisfied when idp_cap_web_configurable_allowed and configurable is enabled and AAD CAP is success" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)
        GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
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

      test "targets are not satisfied when idp_cap_web_configurable_allowed and configurable is enabled and AAD CAP is failure" do
        GitHub.flipper[:idp_cap_for_web].enable(@business)
        GitHub.flipper[:idp_cap_web_configurable_allowed].enable(@business)
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
end
