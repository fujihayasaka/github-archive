# typed: true
# frozen_string_literal: true

require "test_helper"

class Businesses::LicenseCountComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  fixtures do
    @business = create(:business)
  end

  test "renders the consumed license count" do
    render_inline(Businesses::LicenseCountComponent.new(
      business:          @business,
      consumed_licenses: 100
    ))

    assert_text "100"
  end

  test "renders the consumed and total license counts" do
    render_inline(Businesses::LicenseCountComponent.new(
      business:          @business,
      consumed_licenses: 100,
      total_licenses:    1000
    ), allowed_queries: 1)

    assert_text "100 / 1,000"
  end

  test "does not render totals when the business has a metered plan" do
    @business.customer.update_attribute(:metered_ghe, true)

    render_inline(Businesses::LicenseCountComponent.new(
      business:          @business,
      consumed_licenses: 100,
      total_licenses:    1000
    ), allowed_queries: 1)

    assert_text "100"
    refute_text "100 / 1,000"
  end
end
