# typed: true
# frozen_string_literal: true

require "test_helper"

class UserPropensityCopilotBusinessTest < GitHub::TestCase
  skip_enterprise
  skip_with_all_emus

  fixtures do
    @user = create(:user)
    @org = create(:organization, plan: "business")
    @org.add_admin(@user)

    @copilot_user = create(:user)
    @copilot_org = create(:organization, plan: "business")
    Copilot::Organization.new(@copilot_org).enable_copilot!
    @copilot_org.add_admin(@copilot_user)
  end

  setup do
    enable_feature_flag(:copilot_business_propensity_nudge)
  end

  test "finding a user's propensity" do
    propensity = create_user_propensity

    refute_nil propensity
  end

  test "finding a user's propensity when it doesn't exist" do
    propensity = UserPropensity::CopilotBusiness.find(@user)
    assert_nil propensity
  end

  test "finding a user's propensity with the feature flag disabled" do
    disable_feature_flag(:copilot_business_propensity_nudge)

    Site::KV.store.expects(:get).never

    UserPropensity::CopilotBusiness.find(@user)
  end

  test "show_explore_nudge? returns true for owners with low propensity" do
    propensity = build_user_propensity(group: "low", relationship_type: "owner")

    assert propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? returns false for owners with high propensity" do
    propensity = build_user_propensity(group: "high", relationship_type: "owner")

    refute propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? returns false for owners with medium propensity" do
    propensity = build_user_propensity(group: "medium", relationship_type: "owner")

    refute propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? returns false for non-owner relationship_types" do
    propensity = build_user_propensity(group: "low", relationship_type: "member")

    refute propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? is false for non-admin users" do
    non_admin = create(:user)
    @org.add_member(non_admin)

    # Testing if a user is marked as an "owner" in the model but doesn't actually have admin access to the Org
    propensity = build_user_propensity(user: non_admin, group: "low", relationship_type: "owner")

    refute propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? returns false if the user is an enterprise managed user" do
    emu = create(:emu)
    propensity = build_user_propensity(group: "low", relationship_type: "owner")
    propensity = UserPropensity::CopilotBusiness.find(emu)

    refute propensity&.show_explore_nudge?
  end

  test "show_explore_nudge? returns false if the organization already has Copilot Business enabled" do
    propensity = build_user_propensity(user: @copilot_user, org: @copilot_org, group: "low", relationship_type: "owner")

    refute propensity&.show_explore_nudge?
  end

  test "show_purchase_nudge? returns false for owners with low propensity" do

    propensity = build_user_propensity(group: "low", relationship_type: "owner")

    refute propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? returns true for owners with high propensity" do
    propensity = build_user_propensity(group: "high", relationship_type: "owner")

    assert propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? returns true for owners with medium propensity" do
    propensity = build_user_propensity(group: "medium", relationship_type: "owner")

    assert propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? returns false for non-owner relationship_types" do
    @org.add_member(@user)
    propensity = build_user_propensity(group: "low", relationship_type: "member")

    refute propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? is false for non-admin users" do
    non_admin = create(:user)
    @org.add_member(non_admin)

    # Testing if a user is marked as an "owner" in the model but doesn't actually have admin access to the Org
    propensity = build_user_propensity(user: non_admin, group: "low", relationship_type: "owner")

    refute propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? returns false if the user is an enterprise managed user" do
    emu = create(:emu)
    propensity = build_user_propensity(group: "high", relationship_type: "owner")
    propensity = UserPropensity::CopilotBusiness.find(emu)

    refute propensity&.show_purchase_nudge?
  end

  test "show_purchase_nudge? returns false if the organization already has Copilot Business enabled" do
    propensity = build_user_propensity(user: @copilot_user, org: @copilot_org, group: "high", relationship_type: "owner")

    refute propensity&.show_purchase_nudge?
  end

  test "group returns the propensity group" do
    propensity = build_user_propensity(group: "high")
    assert_equal UserPropensity::CopilotBusiness::Group::High, propensity&.group

    propensity = build_user_propensity(group: "medium")
    assert_equal UserPropensity::CopilotBusiness::Group::Medium, propensity&.group

    propensity = build_user_propensity(group: "low")
    assert_equal UserPropensity::CopilotBusiness::Group::Low, propensity&.group
  end

  test "organization_login returns the organization login" do
    propensity = build_user_propensity

    assert_equal @org.display_login, propensity&.organization_login
  end

  def create_user_propensity(user: @user, org: @org, group: "low", relationship_type: "owner")
    build_user_propensity(user:, org:, group:, relationship_type:).tap do |propensity|
      propensity.save
    end
  end

  def build_user_propensity(user: @user, org: @org, group: "low", relationship_type: "owner")
    UserPropensity::CopilotBusiness.new(
      user:,
      relationship_type:,
      group: UserPropensity::CopilotBusiness::Group.deserialize(group),
      organization_id: org.id,
      organization_login: org.display_login,
      org_propensity_score: 0.5
    )
  end
end
