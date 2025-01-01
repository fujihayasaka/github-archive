# typed: true
# frozen_string_literal: true

require "test_helper"

class BundledLicenseAssignmentsControllerTest < GitHub::IntegrationTestCase
  fixtures do
    @staff = create :staff_admin_user
    @business = create(:business)
  end

  setup do
    as @staff
  end

  context "#index" do
    test "renders 404 if no business is found" do
      get "/stafftools/enterprises/not-a-biz/bundled_license_assignments"
      assert_response :not_found
    end

    test "renders assignments for the business" do
      create_list(:licensing_bundled_license_assignment, 3, business: @business)

      get "/stafftools/enterprises/#{@business.slug}/bundled_license_assignments"
      assert_response 200
      assert_includes response.body, "Bundled license assignments (0 linked, 3 unlinked) for #{@business.name}"
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 3
    end

    test "renders no assignments" do
      business_with_no_assignments = create(:business)

      get "/stafftools/enterprises/#{business_with_no_assignments.slug}/bundled_license_assignments"
      assert_response 200
      assert_includes response.body, "Bundled license assignments (0 linked, 0 unlinked) for #{business_with_no_assignments.name}"
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 0
    end

    test "supports searching for assignments by email" do
      create_list(:licensing_bundled_license_assignment, 3, business: @business)
      assignment = create :licensing_bundled_license_assignment, \
        business: @business, email: "someonewithalicense@example.com"

      get "/stafftools/enterprises/#{@business.slug}/bundled_license_assignments", params: {
        query: "someonewithalicense"
      }

      assert_response 200
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 1
      assert_select "[data-test-selector=bundled-license-assignment-#{assignment.id}-label]", count: 1
    end

    test "supports pagination" do
      # Stafftools::BundledLicenseAssignmentsController.any_instance.stubs(:PER_PAGE).returns(1)
      create_list(:licensing_bundled_license_assignment, 21, business: @business)

      get "/stafftools/enterprises/#{@business}/bundled_license_assignments"

      assert_response 200
      assert_select "[data-test-selector=bundled-license-assignment-pagination]", count: 1
    end
  end

  context "#perform_user_link_job" do
    test "enqueues SetUserFromBusinessOnBundledLicenseAssignmentJob" do
      assignment = create(:licensing_bundled_license_assignment, business: @business)
      assert_enqueued_jobs(1, only: Licensing::SetUserFromBusinessOnBundledLicenseAssignmentJob) do
        post "/stafftools/enterprises/#{@business.slug}/bundled_license_assignments/#{assignment.id}/perform_user_link_job"
      end
    end
  end

  context "#orphaned" do
    test "renders no orphaned assignments" do
      create_list(:licensing_bundled_license_assignment, 3, business: @business)

      get "stafftools/bundled_license_assignments/orphaned"
      assert_response 200
      assert_includes response.body, "Orphaned bundled license assignments"
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 0
    end

    test "renders orphaned assignments" do
      create_list(:licensing_bundled_license_assignment, 3)

      get "stafftools/bundled_license_assignments/orphaned"
      assert_response 200
      assert_includes response.body, "Orphaned bundled license assignments"
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 3
    end

    test "supports searching for assignments by email" do
      create_list(:licensing_bundled_license_assignment, 3)
      assignment = create :licensing_bundled_license_assignment, email: "someonewithalicense@example.com"

      get "stafftools/bundled_license_assignments/orphaned", params: {
        query: "someonewithalicense"
      }

      assert_response 200
      assert_select "[data-test-selector=bundled-license-assignment-item]", count: 1
      assert_select "[data-test-selector=bundled-license-assignment-#{assignment.id}-label]", count: 1
    end
  end
end if GitHub.billing_enabled?
