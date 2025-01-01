# typed: true
# frozen_string_literal: true

require "test_helper"

class OrgsPaginatedConsumedLicensesTest < GitHub::TestCase
  fixtures do
    @user1 = create(:user, login: "one")
    @user2 = create(:user, login: "two")
    @user3 = create(:user, login: "three")
  end

  setup do
    @fake_license_attributer = OpenStruct.new(
      user_ids: [@user3, @user2, @user1].pluck(:id).to_set,
      emails: ["c@example.com", "b@example.com", "a@example.com"].to_set,
      unique_count: 6,
    )
  end

  test "returns users first, sorted by ID" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 1, per_page: 2)

    assert_equal %w[one two], paginated_licenses.to_a.map(&:display_name)
  end

  test "returns a mix of users and emails (sorted alphabetically) if there's not enough emails for a full page" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 2, per_page: 2)

    assert_equal ["three", "a@example.com"], paginated_licenses.to_a.map(&:display_name)
  end

  test "returns emails, sorted alphabetically, once it runs out of users" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 3, per_page: 2)

    assert_equal ["b@example.com", "c@example.com"], paginated_licenses.to_a.map(&:display_name)
  end

  test "returns an empty array when there's nothing left" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 4, per_page: 2)

    assert_equal [], paginated_licenses.to_a
  end

  test "returns an empty array when a large page is passed in" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 40, per_page: 2)

    assert_equal [], paginated_licenses.to_a
  end

  test "sets the current page to 1 if something less than 1 is passed in" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: -1)

    assert_equal 1, paginated_licenses.current_page
  end

  test "exposes some metadata about the size of the result set" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: 1, per_page: 4)

    assert_equal 6, paginated_licenses.total_count
    assert_equal 2, paginated_licenses.total_pages
  end

  test "defaults page and page size" do
    paginated_licenses = Orgs::PaginatedConsumedLicenses.new(license_attributer: @fake_license_attributer, page: nil)

    assert_equal 1, paginated_licenses.current_page
    assert_equal WillPaginate.per_page, paginated_licenses.per_page
  end
end
