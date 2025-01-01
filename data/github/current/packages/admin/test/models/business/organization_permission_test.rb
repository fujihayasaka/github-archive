# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessOrganizationPermissionTest < GitHub::TestCase
  fixtures do
    @admin = create(:user)
    @business = create(:business, owners: [@admin])
    @organization = create(:organization, business: @business, admins: [@admin])
  end

  context "#can_create_organization?" do
    if GitHub.single_business_environment?
      test "returns true on GHES even when there are no seats left" do
        new_owner = create :user
        @business.update(seats: 1)
        @business.add_owner new_owner, actor: @admin
        assert_predicate Business::OrganizationPermission.new(@business, new_owner), :can_create_organization?
      end
    else
      test "returns false if business is downgraded to free plan" do
        @business.update(seats: 2)
        @business.downgrade_to_free_plan
        refute Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end

      test "returns false if business is basic" do
        @business.update(seats_plan_type: :basic)
        refute Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end

      test "returns true if business has remaining licenses" do
        @business.update(seats: 2)
        assert Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end

      test "returns false if business has no remaining licenses and current user has no license" do
        @business.update(seats: 1)
        refute Business::OrganizationPermission.new(@business, create(:user)).can_create_organization?
      end

      test "returns true if business has no remaining licenses and current user has a license" do
        @business.update(seats: 1)
        assert Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end

      test "returns true if business has remaining bundle licenses and the current user does not have a license" do
        @business.update(seats: 1)
        create(:enterprise_agreement, :visual_studio_bundle, business: @business, seats: 1)
        assert Business::OrganizationPermission.new(@business, create(:user)).can_create_organization?
      end

      test "returns true if business has no remaining licenses and current user has no license but check_licenses is false" do
        @business.update(seats: 1)
        assert Business::OrganizationPermission.new(@business, create(:user)).can_create_organization?(check_licenses: false)
      end

      test "returns true if the business has metered billing enabled" do
        @business.customer.metered_ghe = true
        assert Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end

      test "returns false if the business has metered billing enabled but has been downgraded to a free plan" do
        @business.customer.metered_ghe = true
        @business.downgrade_to_free_plan
        refute Business::OrganizationPermission.new(@business, @admin).can_create_organization?
      end
    end
  end
end
