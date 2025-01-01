# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::VolumeLicensesViewTest < GitHub::TestCase
  context ".for_business" do
    test "uses the number of seats on the enterprise agreement and volume licence counts to calculate the total available and consumed licenses" do
      business = create(:business)
      create(:enterprise_agreement, business: business, seats: 1)
      organization = create(:organization, business: business)
      business.reload # make business aware of organization

      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business, user: business.owners.first)
      create(:licensing_bundled_license_assignment, business: business, user: user)
      organization.add_member(business.owners.first)
      organization.add_member(user)
      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

      # Need to load a fresh business to avoid stale memoization
      view = Businesses::VolumeLicensesView.for_business(Business.find(business.id))

      assert_equal 1, view.total_available
      assert_equal 2, view.consumed
    end

    test "excludes non-linked to user volume licences to calculate consumed licenses" do
      business = create(:business)
      create(:enterprise_agreement, business: business, seats: 1)
      organization = create(:organization, business: business)
      business.reload # make business aware of organization

      user = create(:user)
      create(:licensing_bundled_license_assignment, business: business)
      create(:licensing_bundled_license_assignment, business: business)
      organization.add_member(business.owners.first)
      organization.add_member(user)
      perform_enqueued_jobs only: BusinessUpdateLicenseUsageJob

      # Need to load a fresh business to avoid stale memoization
      view = Businesses::VolumeLicensesView.for_business(Business.find(business.id))

      assert_equal 0, view.consumed
    end
  end

  context "#over_limit?" do
    test "returns true when there are more consumed volume licenses than available" do
      view = Businesses::VolumeLicensesView.new(consumed: 2, total_available: 1)

      assert view.over_limit?
    end

    test "returns false when there are the same number of consumed volume licenses as available licenses" do
      view = Businesses::VolumeLicensesView.new(consumed: 1, total_available: 1)

      refute view.over_limit?
    end

    test "returns false when there are fewer consumed volume licenses than the total available" do
      view = Businesses::VolumeLicensesView.new(consumed: 1, total_available: 2)

      refute view.over_limit?
    end
  end

  context "#maxed_out?" do
    test "returns true when there are more consumed volume licenses than available" do
      view = Businesses::VolumeLicensesView.new(consumed: 2, total_available: 1)

      assert view.maxed_out?
    end

    test "returns true when there are the same number of consumed volume licenses as available licenses" do
      view = Businesses::VolumeLicensesView.new(consumed: 1, total_available: 1)

      assert view.maxed_out?
    end

    test "returns false when there are fewer consumed volume licenses than the total available" do
      view = Businesses::VolumeLicensesView.new(consumed: 1, total_available: 2)

      refute view.maxed_out?
    end
  end
end
