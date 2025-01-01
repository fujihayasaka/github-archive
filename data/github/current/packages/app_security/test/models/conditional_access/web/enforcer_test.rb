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

class WebEnforcerTest < GitHub::IntegrationTestCase
  skip_enterprise

  fixtures do
    @user = create(:user)
    @emu = create(:emu, :owner)
    @emu_business = @emu.enterprise_managed_business
  end

  context "enterprise-managed user" do
    test "satisfied for emu user and emu business tfca" do
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: @emu_business)
      enforcer = ConditionalAccess::Web::Enforcer.new(controller)

      results = enforcer.evaluate_conditional_access_policies(controller, policies: [:emu_ownership])
      assert_equal 1, results.size
      assert_equal :emu_ownership, results.keys.first
      assert_equal :satisfied, results.values.first
    end

    test "unsatisfied for emu user and non-emu business tfca" do
      org = create(:organization)
      controller = TestEmuApplicationController.new(current_user: @emu, tfca: org)
      enforcer = ConditionalAccess::Web::Enforcer.new(controller)

      results = enforcer.evaluate_conditional_access_policies(controller, policies: [:emu_ownership])
      assert_equal 1, results.size
      assert_equal :emu_ownership, results.keys.first
      assert_equal :unsatisfied, results.values.first
    end

    test "inapplicable for non emu user" do
      controller = TestEmuApplicationController.new(current_user: @user, tfca: @emu_business)
      enforcer = ConditionalAccess::Web::Enforcer.new(controller)

      results = enforcer.evaluate_conditional_access_policies(controller, policies: [:emu_ownership])
      assert_equal 1, results.size
      assert_equal :emu_ownership, results.keys.first
      assert_equal :inapplicable, results.values.first
    end

    test "conditional access policies that will run" do
      controller = TestEmuApplicationController.new(current_user: @user, tfca: @emu_business)
      enforcer = ConditionalAccess::Web::Enforcer.new(controller)

      assert_equal [:enterprise_access_verification, :tenant_verification, :emu_visibility, :emu_ownership, :ip_allowlist, :two_factor, :external_conditional_access_policy], enforcer.conditional_access_policies
      assert_equal [:enterprise_access_verification, :tenant_verification, :emu_visibility, :emu_ownership, :ip_allowlist, :two_factor, :external_conditional_access_policy], enforcer.registered_policies
    end
  end
end
