# typed: true
# frozen_string_literal: true
require "test_helper"

class PublicFilterTest < GitHub::TestCase
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @emu_business = @emu.enterprise_managed_business
    @emu_org = create(:organization, business: @emu_business, admin: @emu_org)

    @admin = create :user
    @business = create :business, owners: [@admin]
  end

  class TestApp < Api::App
    def initialize(current_user)
      @current_user = current_user
    end

    def current_user
      @current_user
    end
  end

  context "conditional access policies" do
    test "lists conditional access policies with feature flag disabled" do
      GitHub.flipper[:idp_cap_for_filters].disable

      app = TestApp.new!(@emu)
      filter = ConditionalAccess::Api::Public::Filter.new(app)
      assert_same_elements [
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ], filter.conditional_access_policies
    end

    test "lists conditional access policies with feature flag enabled only on single business", skip_all_features: true do
      GitHub.flipper[:idp_cap_for_filters].enable(@emu)
      app = TestApp.new!(@emu)
      filter = ConditionalAccess::Api::Public::Filter.new(app)

      # contains external_conditional_access_policy because the feature flag is enabled on the EMU
      assert_same_elements [
        :external_conditional_access_policy,
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ], filter.conditional_access_policies

      app = TestApp.new!(@user)
      filter = ConditionalAccess::Api::Public::Filter.new(app)

      # does not contain external_conditional_access_policy because the feature flag is not enabled on the user
      assert_same_elements [
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ], filter.conditional_access_policies
    end

    test "lists conditional access policies with feature flag fully enabled" do
      GitHub.flipper[:idp_cap_for_filters].enable

      app = TestApp.new!(@emu)
      filter = ConditionalAccess::Api::Public::Filter.new(app)
      assert_same_elements [
        :external_conditional_access_policy,
        :ip_allowlist,
        :legacy_personal_access_tokens,
        :personal_access_tokens,
        :saml,
        :two_factor,
        :personal_access_tokens_expiration_limit
      ], filter.conditional_access_policies
    end
  end
end
