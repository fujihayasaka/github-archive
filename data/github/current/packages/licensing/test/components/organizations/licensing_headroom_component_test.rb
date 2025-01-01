# typed: true
# frozen_string_literal: true

require "test_helper"

class Organizations::LicensingHeadroomComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @organization = create(:organization, plan: :business_plus)
  end

  test "renders information about the remaining licenses/seats" do
    component = Organizations::LicensingHeadroomComponent.new(
      remaining_units: 25,
      unit_of_measure: "seat",
      more_units_link_markup: "more seats link",
      more_information_markup: "more info"
    )
    render_inline(component, allowed_queries: 0)

    assert_text "25 memberships left"
  end
end
