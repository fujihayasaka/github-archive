# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::EnterpriseLicensesViewTest < GitHub::TestCase
  unless GitHub.single_business_environment?
    context ".for_business" do
      test "uses the number of seats and enterprise licence counts to calculate the total available and consumed licenses" do
        admin = create(:user)
        user = create(:user)
        org = create(:organization, admins: [admin], public_members: [user])
        business = create(:business, seats: 3, organizations: [org])

        view = Businesses::EnterpriseLicensesView.for_business(business.reload)

        assert_equal 3, view.total_available
        assert_equal 2, view.consumed
      end
    end

    context "#maxed_out?" do
      test "returns true when there are more consumed licenses than available" do
        view = Businesses::EnterpriseLicensesView.new(consumed: 2, total_available: 1)

        assert view.maxed_out?
      end

      test "returns true when there are the same number of consumed licenses as available licenses" do
        view = Businesses::EnterpriseLicensesView.new(consumed: 1, total_available: 1)

        assert view.maxed_out?
      end

      test "returns false when there are fewer consumed licenses than the total available" do
        view = Businesses::EnterpriseLicensesView.new(consumed: 1, total_available: 2)

        refute view.maxed_out?
      end
    end
  end
end
