# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessLicenseUsageTest < GitHub::TestCase
  fixtures do
    @organization = create(:organization)
    @user = create :user, login: "user"
    @organization.add_member(@user)
    @other_org = create(:organization)
    @other_private_repo = create(:private_repository, owner: @other_org)
    @business = create(:business, organizations: [@organization, @other_org])
  end

  context "#update_usage" do
    test "sets consumed_enterprise_licenses" do
      @business.license_usage.destroy
      usage = @business.build_license_usage
      usage.update_usage(@business)
      assert_equal 3, usage.consumed_enterprise_licenses
    end

    test "sets consumed_volume_licenses" do
      business = create(:business, :volume_licensed, seats: 0)
      create(:enterprise_agreement, :visual_studio_bundle, business: business, seats: 1)
      2.times { create(:licensing_bundled_license_assignment, business: business, user: create(:user)) }
      business.license_usage.destroy
      usage = business.build_license_usage
      usage.update_usage(business)
      assert_equal 2, usage.consumed_volume_licenses
    end
  end

  context "#add_consumed_seats" do
    test "updates count and generated at" do
      assert_equal 3, @business.license_usage.consumed_enterprise_licenses
      old_generated_at = @business.license_usage.generated_at
      @business.license_usage.add_consumed_seats(10)
      assert_equal 13, @business.license_usage.consumed_enterprise_licenses
      refute_equal old_generated_at, @business.license_usage.generated_at
    end
  end
end unless GitHub.single_business_environment?
