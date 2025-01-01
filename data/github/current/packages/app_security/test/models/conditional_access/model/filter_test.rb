# typed: true
# frozen_string_literal: true

require "test_helper"

class ModelFilterTest < GitHub::IntegrationTestCase
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @emu_business = @emu.enterprise_managed_business
    @emu_org = create(:organization, business: @emu_business, admin: @emu_org)

    @admin = create :user
    @business = create :business, owners: [@admin]
  end

  setup do
    @filter = ConditionalAccess::Model::Filter::new(nil, actor: @emu, location: :test)
  end

  context "conditional_access_policies" do
    test "lists conditional access policies" do
      # contains :external_conditional_access_policy because the feature flag is enabled for the business
      assert_same_elements [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor], @filter.conditional_access_policies

      # contains :external_conditional_access_policy because the feature flag is enabled for all businesses
      non_emu_filter = ConditionalAccess::Model::Filter::new(nil, actor: @admin, location: :test)
      assert_same_elements [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor], non_emu_filter.conditional_access_policies
    end
  end
end
