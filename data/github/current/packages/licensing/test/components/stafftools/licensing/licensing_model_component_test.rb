# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::Licensing::LicensingModelComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "renders for metered business" do
    business = create(:business)
    business.customer.update! metered_plan: "true"
    render_inline(Stafftools::Licensing::LicensingModelComponent.new(billable_entity: business), allowed_queries: 1)
    assert_test_selector("license-type-status", text: "Licensing model: Metered")
  end

  test "renders for non-metered business" do
    business = create(:business)
    render_inline(Stafftools::Licensing::LicensingModelComponent.new(billable_entity: business), allowed_queries: 1)
    assert_test_selector("license-type-status", text: "Licensing model: Volume")
  end
end
