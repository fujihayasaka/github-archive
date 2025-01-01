# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Businesses::EnterpriseLicensingViewTest < GitHub::TestCase
  include Billing::ApiTestHelpers

  def create_view(business:)
    Stafftools::Businesses::EnterpriseLicensingView.new(business:)
  end

  context "sales_serve_over_consumption" do
    test "returns true if the business has more consumed enterprise licenses than purchased & has sales-serve plan" do
      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization)
      org.add_member(user1)
      org.add_member(user2)
      business = create(:business, organizations: [org], seats: 4)
      create(:billing_sales_serve_plan_subscription, customer: business.customer)
      business.update(seats: 2)

      view = create_view(business:)
      assert view.sales_serve_over_consumption
    end

    test "returns false without sales-serve plan" do
      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization)
      org.add_member(user1)
      org.add_member(user2)
      business = create(:business, organizations: [org], seats: 4)
      business.update(seats: 2)

      view = create_view(business:)
      refute view.sales_serve_over_consumption
    end

    test "returns false if the business has not consumed more enterprise licenses than purchased" do
      user1 = create(:user)
      user2 = create(:user)
      org = create(:organization)
      org.add_member(user1)
      org.add_member(user2)
      business = create(:business, organizations: [org], seats: 100)
      create(:billing_sales_serve_plan_subscription, customer: business.customer)

      view = create_view(business:)
      refute view.sales_serve_over_consumption
    end
  end
end
