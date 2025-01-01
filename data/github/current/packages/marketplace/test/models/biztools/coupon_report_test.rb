# typed: true
# frozen_string_literal: true

require "test_helper"

class BiztoolsCouponReportTest < GitHub::TestCase
  fixtures do
    @coupon = create(:coupon, limit: 2)
    @org = create(:organization)
    @user = create(:user)

    @org_redemption = create(:coupon_redemption, coupon: @coupon, billable_entity: @org)
    @user_redemption = create(:coupon_redemption, coupon: @coupon, billable_entity: @user, created_at: @org_redemption.created_at + 1.day)
  end

  setup do
    @report = Biztools::CouponReport.new(@coupon)
  end

  context "#generate" do
    test "generates a CSV coupon report" do
      headers = "Account type,Login,Name,Location,Members,Private repositories,Public repositories,Redeemed on"
      org_entry = "Organization,#{@org.login},#{@org.profile.try(:name)},#{@org.profile.try(:location)},#{@org.members.count},#{@org.private_repositories.count},#{@org.public_repositories.count},#{@org_redemption.created_at.to_date}"
      user_entry = "User,#{@user.login},#{@user.profile.try(:name)},#{@user.profile.try(:location)},0,#{@user.private_repositories.count},#{@user.public_repositories.count},#{@user_redemption.created_at.to_date}"

      csv = @report.generate
      assert_match headers, csv
      assert_match org_entry, csv
      assert_match user_entry, csv
    end
  end
end
