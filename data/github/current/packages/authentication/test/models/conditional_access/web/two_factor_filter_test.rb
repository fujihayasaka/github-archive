# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorFilterTestController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def authorize
    target = User.find_by(id: params[:target])
    resources = cap_filter.authorized_resource_ids(target&.repositories)
    msg = { resources: resources }
    render json: msg
  end

  def cap_filter
    f = super
    f.expects(:conditional_access_policies).returns([:two_factor]).at_least_once
    f
  end
end

class TwoFactorFilterTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user
    @org = create :business_plus_org, admin: @owner
    @repo1 = create(:private_repository, owner: @org)
    @repo2 = create(:private_repository, owner: @org)
    @repo3 = create(:public_repository, owner: @org)

    @direct_member_with_2fa = create :user
    make_two_factor_credential(@direct_member_with_2fa)
    @direct_member_without_2fa = create :user

    @org.add_member @direct_member_with_2fa
    @org.add_member @direct_member_without_2fa

    @org.enable_two_factor_required(actor: @owner)
    assert @org.member?(@direct_member_without_2fa)
    assert @org.two_factor_requirement_enabled?
  end

  setup_once do
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
    TestRoutes.draw do
      get "/authorize/:target", to: "two_factor_filter_test#authorize"
    end
  end

  test "authorized returns all resources for user with 2FA" do
    as @direct_member_with_2fa
    get "/authorize/#{@org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_same_elements @org.repositories.pluck(:id), authorized_resources
  end

  test "authorized returns no resources for user without 2FA" do
    as @direct_member_without_2fa
    get "/authorize/#{@org.id}"
    authorized_resources = JSON.parse(response.body)["resources"]
    assert_empty authorized_resources
  end
end
