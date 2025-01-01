# typed: true
# frozen_string_literal: true

require "test_helper"

class Growth::CopilotOrganizationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @business = create(:business, owners: [@owner])
    @organization = create(:organization, admins: [@owner], business: @business)
  end

  context "#can_enable_org_to_assign_seats?" do
    test "returns true if organization is billed through an enterprise and user owns it" do
      assert Copilot::Organization.new(@organization).can_enable_org_to_assign_seats?(@owner)
    end

    test "returns false if user is nil" do
      refute Copilot::Organization.new(@organization).can_enable_org_to_assign_seats?(nil)
    end

    test "returns false if organization is not billed through an enterprise" do
      non_enterprise_org = create(:organization, admins: [@owner])

      refute Copilot::Organization.new(non_enterprise_org).can_enable_org_to_assign_seats?(@owner)
    end

    test "returns false if organization is billed through an enterprise but user is only org admin" do
      another_user = create(:user)
      another_user_org = create(:organization, admins: [another_user], business: @business)

      refute Copilot::Organization.new(another_user_org).can_enable_org_to_assign_seats?(another_user)
    end

    test "returns false if enterprise is on trial" do
      trial_business = create(:business, trial_expires_at: 3.days.from_now, owners: [@owner])
      trial_business_org = create(:organization, admins: [@owner], business: trial_business)

      refute Copilot::Organization.new(trial_business_org).can_enable_org_to_assign_seats?(@owner)
    end
  end
end if GitHub.copilot_enabled?
