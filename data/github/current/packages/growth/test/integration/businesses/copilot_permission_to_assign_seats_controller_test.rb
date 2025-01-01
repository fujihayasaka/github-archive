# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::CopilotPermissionToAssignSeatsControllerTest < GitHub::IntegrationTestCase
  include HydroTestHelpers

  skip_with_all_emus
  skip_enterprise

  fixtures do
    @owner = create(:user)
    @business = create(:business, owners: [@owner])
    @organization = create(:organization, business: @business, admin: @owner)
  end

  test "can enable permission to assign seats for a org that is on a business account" do
    refute Copilot::Organization.new(@organization).copilot_enabled?
    as @owner

    put "/enterprises/#{@business.slug}/settings/#{@organization.display_login}/copilot_permission_to_assign_seats"
    assert_redirected_to settings_org_copilot_seat_management_path(@organization)

    assert_hydro_published_partial({
      category: "copilot_permission_to_assign_seats",
      action: "enabled_org",
      label: "user:#{@owner.id};org:#{@organization.id}",
    }, schema: "github.analytics.v0.Event")
    assert Copilot::Organization.new(@organization.reload).copilot_enabled?
    assert Copilot::Organization.new(@organization).seat_management_enabled_for_selected?
  end

  test "does not disable other orgs when enabling permission to assign seats for a org that is on a business account" do
    another_org = create(:organization, business: @business, admin: @owner)
    Copilot::Business.new(@business).enable_copilot_for_selected_organizations!([another_org.id])
    Copilot::Organization.new(another_org).seat_management_allow_all!
    assert Copilot::Organization.new(another_org.reload).copilot_enabled?
    as @owner

    put "/enterprises/#{@business.slug}/settings/#{@organization.display_login}/copilot_permission_to_assign_seats"
    assert_redirected_to settings_org_copilot_seat_management_path(@organization)

    assert Copilot::Organization.new(@organization.reload).copilot_enabled?
    assert Copilot::Organization.new(another_org.reload).copilot_enabled?
  end

  test "does not change policy to enabled_for_selected if already enabled for all organizations" do
    Copilot::Business.new(@business).enable_copilot_for_all_organizations!
    Copilot::Organization.new(@organization).seat_management_allow_all!
    as @owner

    put "/enterprises/#{@business.slug}/settings/#{@organization.display_login}/copilot_permission_to_assign_seats"
    assert_redirected_to settings_org_copilot_seat_management_path(@organization)

    assert Copilot::Organization.new(@organization.reload).seat_management_enabled_for_all?
    assert Copilot::Business.new(@business.reload).copilot_enabled_for_all_organizations?
  end

  test "does not allow to enable permission to assign seats when user is not the enterprise owner" do
    another_user = create(:user)
    @organization.add_admin(another_user, adder: @owner)
    @business.billing.add_manager(another_user, actor: @owner)
    as another_user

    put "/enterprises/#{@business.slug}/settings/#{@organization.display_login}/copilot_permission_to_assign_seats"

    assert_response :not_found
  end

  test "does not allow to enable permission to assign seats when user is not the organization owner" do
    another_user = create(:user)
    @organization.add_member(another_user)
    @business.add_owner(another_user, actor: @owner)
    as another_user

    put "/enterprises/#{@business.slug}/settings/#{@organization.display_login}/copilot_permission_to_assign_seats"

    assert_response :not_found
  end
end
