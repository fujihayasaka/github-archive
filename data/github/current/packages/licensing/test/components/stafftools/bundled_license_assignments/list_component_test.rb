# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::BundledLicenseAssignments::ListComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "renders with no pagination" do
    assignments = create_list(:licensing_bundled_license_assignment, 2).paginate(page: 1, per_page: 5)

    render_inline(Stafftools::BundledLicenseAssignments::ListComponent.new(
      assignments: assignments,
      header: "Bundled license assignments",
      action: "orphaned"
    ))

    assert_test_selector("bundled-license-assignment-header", count: 1) do |header|
      assert_match /#{assignments.count} Bundled license assignments/, header.text
    end
    assert_test_selector("bundled-license-assignment-item", count: 2)
    assert_test_selector("bundled-license-assignment-pagination", count: 0)
  end

  test "renders with pagination" do
    assignments = create_list(:licensing_bundled_license_assignment, 10).paginate(page: 1, per_page: 5)

    render_inline(Stafftools::BundledLicenseAssignments::ListComponent.new(
      assignments: assignments,
      header: "Bundled license assignments",
      action: "orphaned"
    ))

    assert_test_selector("bundled-license-assignment-header", count: 1) do |header|
      assert_match /#{assignments.count} Bundled license assignments/, header.text
    end
    assert_test_selector("bundled-license-assignment-item", count: 5)
    assert_test_selector("bundled-license-assignment-pagination", count: 1)
  end

  test "renders with search_form_path" do
    business = create :business
    assignments = create_list(:licensing_bundled_license_assignment, 2, business: business)
      .paginate(page: 1, per_page: 5)

    render_inline(Stafftools::BundledLicenseAssignments::ListComponent.new(
      assignments: assignments,
      header: "Bundled license assignments",
      action: "index",
      search_form_path: vc_test_controller.stafftools_enterprise_bundled_license_assignments_path(business)
    ))

    assert_test_selector("bundled-license-assignment-search", count: 1)
    assert_test_selector("bundled-license-assignment-header", count: 1) do |header|
      assert_match /#{assignments.count} Bundled license assignments/, header.text
    end
    assert_test_selector("bundled-license-assignment-item", count: 2)
    assert_test_selector("bundled-license-assignment-pagination", count: 0)
  end
end
