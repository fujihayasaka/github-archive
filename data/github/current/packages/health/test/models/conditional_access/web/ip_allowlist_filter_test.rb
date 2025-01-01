# typed: true
# frozen_string_literal: true

require "test_helper"

class IpAllowlistFilterTestController < ApplicationController
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  def authorized_org_repos
    org = Organization.find_by(id: params[:target])
    resources = cap_filter.authorized_resource_ids(T.must(org).repositories)
    msg = { resources: resources }
    render json: msg
  end

  def authorized_businesses
    resources = cap_filter.authorized_resource_ids(current_user.businesses)
    msg = { resources: resources }
    render json: msg
  end

  def authorized_user_repos
    resources = cap_filter.authorized_resource_ids(current_user.repositories)
    msg = { resources: resources }
    render json: msg
  end

  def authorized_emu_users
    if current_user.enterprise_managed_business.blank?
      raise "Unsupported for current_user. Only supported for EMUs."
    end

    enterprise_managed_business_members = current_user
      .enterprise_managed_business
      .user_accounts
      .includes(:user)
      .map { |account| account&.user }.compact

    resources = cap_filter.authorized_resource_ids(enterprise_managed_business_members)
    msg = { resources: resources }
    render json: msg
  end

  def cap_filter
    f = super
    f.expects(:conditional_access_policies).returns([:ip_allowlist]).at_least_once
    if TestEnv.test_all_features?
      f.expects(:do_authzd_science).returns(true).at_least_once
      f.expects(:authzd_science_policies).returns([:ip_allowlist]).at_least_once
    end
    f
  end
end

class IpAllowlistFilterTest < GitHub::IntegrationTestCase
  fixtures do
    @owner = create :user
    @org = create :business_plus_org, admin: @owner
    @repo1 = create(:private_repository, :minimal, owner: @org)
    @repo2 = create(:private_repository, :minimal, owner: @org)
    @repo3 = create(:public_repository, :minimal, owner: @org)

    @org.enable_ip_allowlist actor: @owner
    create :ip_allowlist_entry, owner: @org, allow_list_value: "10.10.10.0/24"

    @user_with_valid_ip = create :user
    @private_repo_one = create(:private_repository, :minimal, owner: @user_with_valid_ip)
    @user_with_invalid_ip = create :user
    @private_repo_two = create(:private_repository, :minimal, owner: @user_with_invalid_ip)

    @org.add_member @user_with_valid_ip
    @org.add_member @user_with_invalid_ip

    membership = create(:business_organization_membership)
    @business_org = membership.organization
    @business = membership.business
    @business.enable_ip_allowlist actor: @business.owners.first
    create :ip_allowlist_entry, owner: @business, allow_list_value: "10.10.10.0/24"

    @emu = create :emu
    @emu_business = @emu.enterprise_managed_business
    enable_feature_flag(:ip_allowlist_user_level_enforcement, @emu_business)
    @emu_business.enable_ip_allowlist actor: @emu_business.owners.first
    @emu_business.enable_ip_allowlist_user_level_enforcement actor: @emu_business.owners.first
    create :ip_allowlist_entry, owner: @emu_business, active: true, allow_list_value: "10.10.10.0/24"
    @emu_repo = create(:private_repository, :minimal, owner: @emu)
    @other_emu_repo = create(:private_repository, :minimal, owner: @emu)
    @other_emu = create :emu, business: @emu_business
  end

  setup_once do
    ::TestRoutes = ActionDispatch::Routing::RouteSet.new unless defined?(::TestRoutes)
    TestRoutes.draw do
      get "/authorized_org_repos/:target", to: "ip_allowlist_filter_test#authorized_org_repos"
      get "/authorized_businesses", to: "ip_allowlist_filter_test#authorized_businesses"
      get "/authorized_user_repos", to: "ip_allowlist_filter_test#authorized_user_repos"
      get "/authorized_emu_users", to: "ip_allowlist_filter_test#authorized_emu_users"
    end
  end

  context "GET /authorized_org_repos" do
    test "returns all resources for user with allowed IP" do
      request_env["REMOTE_ADDR"] = "10.10.10.10"
      as @user_with_valid_ip
      get "/authorized_org_repos/#{@org.id}"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@repo1.id, @repo2.id, @repo3.id], authorized_resources
    end

    test "returns no resources for user with forbidden IP" do
      request_env["REMOTE_ADDR"] = "130.95.128.2"
      as @user_with_invalid_ip
      get "/authorized_org_repos/#{@org.id}"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_empty authorized_resources
    end
  end

  context "GET /authorized_businesses" do
    test "returns all resources for user with allowed IP" do
      @business_org.add_member(@user_with_valid_ip)

      request_env["REMOTE_ADDR"] = "10.10.10.10"
      as @user_with_valid_ip
      get "/authorized_businesses"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@business.id], authorized_resources
    end

    test "returns no resources for user with forbidden IP" do
      @business_org.add_member(@user_with_invalid_ip)

      request_env["REMOTE_ADDR"] = "130.95.128.2"
      as @user_with_invalid_ip
      get "/authorized_businesses"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_empty authorized_resources
    end
  end

  context "GET /authorized_user_repos" do
    test "returns all resources for regular user with allowed IP" do
      request_env["REMOTE_ADDR"] = "10.10.10.10"
      as @user_with_valid_ip
      get "/authorized_user_repos"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@private_repo_one.id], authorized_resources
    end

    test "returns all resources for regular user with forbidden IP" do
      request_env["REMOTE_ADDR"] = "130.95.128.2"
      as @user_with_invalid_ip
      get "/authorized_user_repos"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@private_repo_two.id], authorized_resources
    end

    test "returns all resources for EMU with allowed IP" do
      request_env["REMOTE_ADDR"] = "10.10.10.10"
      as @emu
      get "/authorized_user_repos"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements [@emu_repo.id, @other_emu_repo.id], authorized_resources
    end

    test "returns no resources for EMU with forbidden IP" do
      request_env["REMOTE_ADDR"] = "130.95.128.2"
      as @emu
      get "/authorized_user_repos"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_empty authorized_resources
    end
  end

  context "GET /authorized_emu_users" do
    test "returns all resources for EMU with allowed IP" do
      request_env["REMOTE_ADDR"] = "10.10.10.10"
      as @emu
      get "/authorized_emu_users"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_same_elements \
        [@emu_business.find_first_emu_owner.id, @emu.id, @other_emu.id],
        authorized_resources
    end

    test "returns no resources for EMU with forbidden IP" do
      request_env["REMOTE_ADDR"] = "130.95.128.2"
      as @emu
      get "/authorized_emu_users"

      authorized_resources = JSON.parse(response.body)["resources"]
      assert_empty authorized_resources
    end
  end
end if GitHub.ip_allowlists_available?
