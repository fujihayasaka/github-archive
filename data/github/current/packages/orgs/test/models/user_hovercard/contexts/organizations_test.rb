# typed: true
# frozen_string_literal: true

require "test_helper"

class UserHovercardContextsOrganizationsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @organizations = create_list(:organization, 3)
    @organizations.each do |org|
      org.add_member(@user)
      org.publicize_member(@user)
    end
  end

  setup do
    @all = Organization.where(id: @organizations.map(&:id))
  end

  test "returns the organization octicon" do
    context = UserHovercard::Contexts::Organizations.new(related: [], all: [], user: @user)

    assert_equal "organization", context.octicon
  end

  test "returns a list of organizations, preferring to show related ones, but counting all" do
    related = @organizations.first

    context = UserHovercard::Contexts::Organizations.new(related: [related], all: @all, user: @user)

    assert_equal "Member of @#{related} and 2 more", context.message
  end

  test "returns a list of ranked organizations if there are no related ones specified, including unranked last" do
    org_a, org_b, org_c = @organizations

    Organization.stubs(:compute_ranked_ids).returns([org_b, org_c].map(&:id))

    context = UserHovercard::Contexts::Organizations.new(related: [], all: @all, user: @user)

    assert_match "Member of @#{org_b}, @#{org_c}, and @#{org_a}", context.message
  end

  context "#total_organization_count" do
    test "returns the total number of organizations" do
      context = UserHovercard::Contexts::Organizations.new(related: [], all: @all, user: @user)

      assert_equal 3, context.total_organization_count
    end
  end
end
