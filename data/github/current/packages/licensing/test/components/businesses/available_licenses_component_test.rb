# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::AvailableLicensesComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  skip_with_all_emus
  skip_enterprise

  fixtures do
    org = create :organization
    @business = create :business, seats: 10_000, organizations: [org]
  end

  test "renders available licenses" do
    render_inline(Businesses::AvailableLicensesComponent.new(
      business: @business,
      available_licenses: @business.available_invitable_licenses
    ), allowed_queries: 1)
    assert_test_selector "available-licenses", text: "9,999"
  end

  test "does not render available licenses for non-trial metered accounts" do
    @business.customer.update_attribute(:metered_plan, true)
    render_inline(Businesses::AvailableLicensesComponent.new(
      business: @business,
      available_licenses: @business.available_invitable_licenses
    ), allowed_queries: 1)
    refute_test_selector "available-licenses", text: "9,999"
  end
end
