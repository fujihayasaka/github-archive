# typed: true
# frozen_string_literal: true

require "test_helper"

class TestEmuApplicationController < ApplicationController
  def initialize(current_user:, tfca:)
    @current_user = current_user
    @target_for_conditional_access = tfca
    @request = Struct.new(:get?)
  end

  def current_user
    @current_user
  end

  def target_for_conditional_access
    @target_for_conditional_access || :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def request
    @request.new(false)
  end
end

class WebFilterTest < GitHub::IntegrationTestCase
  skip_enterprise

  fixtures do
    @emu = create :emu, :owner, provider_type: :oidc
    @emu_business = @emu.enterprise_managed_business
    @emu_org = create(:organization, business: @emu_business, admin: @emu_org)

    @admin = create :user
    @business = create :business, owners: [@admin]
  end

  context "conditional_access_policies" do
    test "lists conditional access policies with feature flag disabled" do
      GitHub.flipper[:idp_cap_for_filters].disable
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: @emu_business)
      filter = ConditionalAccess::Web::Filter.new(controller)

      assert_same_elements [:ip_allowlist, :saml, :two_factor], filter.conditional_access_policies
    end

    test "lists conditional access policies with feature flag only enabled in single business", skip_all_features: true do
      GitHub.flipper[:idp_cap_for_filters].enable(@emu)
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: @emu_business)
      filter = ConditionalAccess::Web::Filter.new(controller)

      # contains external_conditional_access_policy because the feature flag is enabled for the business
      assert_same_elements [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor], filter.conditional_access_policies

      controller = TestEmuApplicationController.new(current_user: @user, tfca: @business)
      filter = ConditionalAccess::Web::Filter.new(controller)

      # does not contain external_conditional_access_policy because the feature flag is not enabled for the business
      assert_same_elements [:ip_allowlist, :saml, :two_factor], filter.conditional_access_policies
    end

    test "lists conditional access policies with feature flag fully enabled" do
      GitHub.flipper[:idp_cap_for_filters].enable
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: @emu_business)
      filter = ConditionalAccess::Web::Filter.new(controller)

      # contains external_conditional_access_policy because the feature flag is enabled for the business
      assert_same_elements [:external_conditional_access_policy, :ip_allowlist, :saml, :two_factor], filter.conditional_access_policies
    end
  end

  context "anonymous?" do
    test "return false when current_user is set" do
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: @emu_business)
      filter = ConditionalAccess::Web::Filter.new(controller)
      refute_predicate filter, :anonymous?
    end

    test "returns true when current_user is not set" do
      controller = TestEmuApplicationController.new(current_user: nil, tfca: @emu_business)
      filter = ConditionalAccess::Web::Filter.new(controller)
      assert_predicate filter, :anonymous?
    end
  end
end
