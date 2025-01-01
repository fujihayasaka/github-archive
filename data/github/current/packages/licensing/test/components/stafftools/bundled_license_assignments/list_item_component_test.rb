# typed: true
# frozen_string_literal: true

require "test_helper"

class Stafftools::BundledLicenseAssignments::ListItemComponentTest < GitHub::TestCase
  include GitHub::ComponentTestHelpers

  test "renders assignment with user" do
    assignment = create(:licensing_bundled_license_assignment, user: create(:user))
    render_inline(Stafftools::BundledLicenseAssignments::ListItemComponent.new(assignment: assignment))

    assert_test_selector("bundled-license-assignment-item")
    assert_selector("img.avatar")
    assert_text(assignment.user.login)
    assert_selector(:css, "a[href='/stafftools/users/#{assignment.user.login}']")
    assert_text("linked")
    assert_text("non-revoked")
  end

  test "renders assignment without user" do
    assignment = create(:licensing_bundled_license_assignment, business: create(:business))
    render_inline(Stafftools::BundledLicenseAssignments::ListItemComponent.new(assignment: assignment))

    assert_test_selector("bundled-license-assignment-item")
    assert_selector("svg.octicon-mail")
    assert_text(assignment.email)
    assert_text("unlinked")
    assert_text("non-revoked")
  end

  test "renders revoked assignment" do
    assignment = create(:licensing_bundled_license_assignment, revoked: true)
    render_inline(Stafftools::BundledLicenseAssignments::ListItemComponent.new(assignment: assignment))

    assert_test_selector("bundled-license-assignment-item")
    assert_selector("svg.octicon-mail")
    assert_text(assignment.email)
    assert_text("unlinked")
    assert_text("revoked")
  end

  test "renders perform user link button" do
    assignment = create(:licensing_bundled_license_assignment, business: create(:business))
    render_inline(Stafftools::BundledLicenseAssignments::ListItemComponent.new(assignment: assignment))

    assert_test_selector("perform-user-link-button")
    assert_text("Perform User Link Job")
  end
end
