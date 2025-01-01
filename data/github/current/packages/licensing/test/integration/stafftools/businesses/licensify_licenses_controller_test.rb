# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBusinessesLicensifyLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper

  fixtures do
    @staff_user = create(:staff_admin_user)
    @non_staff_user = create(:user)
    @business = create(:business, :volume_licensed)
  end

  if GitHub.single_business_environment?
    context "GET /stafftools/enterprises/:slug/licenses" do
      test "404s in single business environment" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/licenses"

        assert_response :not_found
      end
    end
  else
    context "GET /stafftools/enterprises/:slug/licenses" do
      test "404s for non-staff" do
        as @non_staff_user
        get "/stafftools/enterprises/#{@business}/licenses"

        assert_response :not_found
      end

      test "renders for staff" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/licenses"

        assert_response :success
      end

      test "renders licensify-licenses partial" do
        as @staff_user
        get "/stafftools/enterprises/#{@business.slug}/licenses"

        assert_select "react-partial[partial-name=licensify-licenses]"

        embedded_data = get_react_partial_embedded_json("licensify-licenses")

        assert_equal embedded_data["props"]["customerId"], @business.customer.id.to_s
      end

      test "equeues the licensify customer update job" do
        as @staff_user
        post "/stafftools/customers/#{@business.customer_id}/licensify_licenses/sync_customer"

        assert_response :redirect
        assert_enqueued_with job: UpdateCustomerInLicensifyJob, args: [@business.customer_id]
      end
    end
  end
end
