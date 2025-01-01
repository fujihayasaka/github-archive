# typed: true
# frozen_string_literal: true

require "test_helper"

class EmuVisibilityWebTestEnforcer < ConditionalAccess::Enforcer
  include ConditionalAccess::Web::Helpers
  include ConditionalAccess::Web::EmuVisibilityPolicy

  def conditional_access_policies
    [:emu_visibility]
  end
  alias :registered_policies :conditional_access_policies

  def location
    :test
  end
end

class EmuVisibilityWebTestController < ApplicationController
  def index
  end

  def target_for_conditional_access
    Business.find_by(slug: params[:slug])
  end

  def cap_enforcer
    @conditional_access_enforcer ||= EmuVisibilityWebTestEnforcer.new(self)
  end
end

class EmuVisibilityWebTest < GitHub::IntegrationTestCase
  skip_enterprise

  fixtures do
    @random_user = create(:user)
    @emu = create(:emu)
    @emu_biz = @emu.enterprise_managed_business
    @emu_owner = @emu_biz.owners.first
  end

  setup_once do
    TestRoutes.draw do
      get "/index", to: "emu_visibility_web_test#index"
      post "/index", to: "emu_visibility_web_test#index"
    end
  end

  context "404s" do
    test "when SSO redirect disabled" do
      @emu_biz.disable_sso_redirect(actor: @emu_owner)
      as @random_user
      get "/index", params: { slug: @emu_biz.slug }
      assert_response :not_found
    end

    test "when not a GET request" do
      @emu_biz.enable_sso_redirect(actor: @emu_owner)
      as @random_user
      post "/index", params: { slug: @emu_biz.slug }
      assert_response :not_found
    end

    test "when attempting to view a non_emu_with_underscore" do
      @non_emu_with_underscore = create(:user)
      actual_login = @non_emu_with_underscore.login
      # This stubbing is needed because I need to put a non-emu user into a situation where it's display_login contains an underscore to mimic and orphaned EMU user
      User.any_instance.stubs(:login).returns("non_emu_with_underscore")
      as @random_user
      get "/#{actual_login}"
      assert_response :not_found
    end
  end

  context "redirects" do
    test "when GET request and SSO redirect enabled" do
      @emu_biz.enable_sso_redirect(actor: @emu_owner)
      as @random_user
      get "/index", params: { slug: @emu_biz.slug }
      assert_redirected_to business_idm_sso_enterprise_path(@emu_biz, return_to: "http://github.com/index?slug=#{@emu_biz.slug}")
    end
  end
end
