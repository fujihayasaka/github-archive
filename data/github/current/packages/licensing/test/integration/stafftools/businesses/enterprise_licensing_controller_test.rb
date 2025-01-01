# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBusinessesEnterpriseLicensingControllerHttpTest < GitHub::IntegrationTestCase
  include GitHub::ReactPayloadHelper

  fixtures do
    @staff_user = create(:staff_admin_user)
    @non_staff_user = create(:user)

    # Some data needed so we get a valid license CSV generated
    @profile = create(:profile, name: "Johnny Test")
    @user = @profile.user
    @organization = create(:organization, admin: @user)
    @business = create(:business, :volume_licensed, organizations: [@organization])
  end

  setup do
    GitHub.flipper[:licensing_overview_ghe_volume].disable(@staff_user)
  end

  if GitHub.single_business_environment?
    context "GET /stafftools/enterprises/:slug/licenses" do
      test "404s in single business environment" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_response :not_found
      end
    end
  else
    context "GET /stafftools/enterprises/:slug/licenses" do
      test "404s for non-staff" do
        as @non_staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_response :not_found
      end

      test "renders for staff" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_response :success
      end

      test "renders metered ghes license partial for metered customers", skip_with_all_emus: true do
        @business.customer.update(metered_plan: true)

        ghes_license = create(:licensing_ghes_license, business: @business)

        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        embedded_data = get_react_partial_embedded_json("metered-enterprise-server-licenses")

        expected_props = {
          business: {
            slug: @business.slug,
          },
          serverLicenses: [
            ghes_license.as_json(only: [:reference_number, :seats, :expires_at], root: false)
          ],
          consumedEnterpriseLicenses: 1,
          isStafftools: true,
          auditLogQueryUrl: stafftools_audit_log_path(query: "business_id:#{@business.id} action:ghes_license.*"),
        }.as_json

        assert_equal embedded_data["props"], expected_props
        assert_equal embedded_data["props"]["serverLicenses"].length, 1
      end

      test "renders standard license overview for non-metered customers" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_response :success
        assert_select "[data-test-selector='license-overview']"
        assert_select "[data-test-selector='license-overview-ghe']"
        assert_select "[data-test-selector='license-overview-vss']"
        assert_select "[data-test-selector='license-overview-totals']"
      end

      test "renders licensing-enterprise-overview partial if customer is metered" do
        @business.customer.update(metered_plan: true)

        as @staff_user
        get "/stafftools/enterprises/#{@business.slug}/enterprise_licensing"

        assert_select "react-partial[partial-name=licensing-enterprise-overview]"

        embedded_data = get_react_partial_embedded_json("licensing-enterprise-overview")

        assert_equal embedded_data["props"]["slug"], @business.slug
        assert embedded_data["props"]["ghe"]["enterpriseLicensesConsumed"] > 0
      end

      test "does not render licensing-enterprise-overview partial if customer is not metered" do
        @business.customer.update(metered_plan: false)

        as @staff_user
        get "/stafftools/enterprises/#{@business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-enterprise-overview]"
      end

      test "does not render licensing-enterprise-overview partial if customer is copilot-only" do
        @business.customer.update(metered_plan: true)
        @business.update(seats_plan_type: :basic)

        as @staff_user
        get "/stafftools/enterprises/#{@business.slug}/enterprise_licensing"

        refute_select "react-partial[partial-name=licensing-enterprise-overview]"
      end

      test "shows background job form" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"
        assert_select "form[class='js-license-usage-download-form']"
      end

      test "renders a CSV when that format is requested" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing.csv"

        assert_response :success
        assert_match(/^attachment/, response.headers["Content-Disposition"])
      end

      test "renders bundle license assignment navigation" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_includes response.body, "Visual Studio subscription license assignments"
      end

      test "renders Kusto link to view license watermark report" do
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_select "[data-test-selector='license-watermark-kusto-link']"
      end

      test "renders licensify-product-enablements React partial when the user has licensify_product_enablements FF enabled" do
        disable_feature_flag(:licensify_product_enablements)
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        refute_select "react-partial[partial-name='licensify-product-enablements']"

        enable_feature_flag(:licensify_product_enablements, @staff_user)
        as @staff_user
        get "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_select "react-partial[partial-name='licensify-product-enablements']"

        embedded_data = get_react_partial_embedded_json("licensify-product-enablements")
        assert_equal embedded_data["props"], { customerId: @business.customer.id }.as_json
      end
    end

    context "PATCH /stafftools/enterprises/:slug/licenses" do
      test "404s for non-staff" do
        as @non_staff_user
        patch "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_response :not_found
      end

      test "enqueues business update license usage job" do
        as @staff_user
        assert_enqueued_jobs 1, only: BusinessUpdateLicenseUsageJob do
          patch "/stafftools/enterprises/#{@business}/enterprise_licensing"
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"
      end

      test "enqueues business synchronize user accounts job" do
        as @staff_user
        assert_enqueued_jobs 1, only: BusinessUserAccountsSynchronizeJob do
          patch "/stafftools/enterprises/#{@business}/enterprise_licensing"
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"
      end
    end

    context "POST /stafftools/enterprises/:slug/enterprise_licensing/transition_licensing_model" do
      test "404s for non-staff" do
        as @non_staff_user
        post "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model", params: { licensing_model: "metered" }

        assert_response :not_found
      end

      test "enqueues business transition to metered job" do
        as @staff_user
        assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
          post "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model", params: { licensing_model: "metered" }
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"
      end

      test "schedules business transition to metered job for the future" do
        as @staff_user
        assert_enqueued_jobs 0, only: Licensing::TransitionEnterpriseToMeteredLicensingJob do
          post "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model", params: { licensing_model: "metered", transition_date: Date.tomorrow }
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"

        transition = Licensing::LicensingModelTransition.find_by(customer: @business.customer)
        assert_equal T.must(transition).transition_date, Date.tomorrow
      end

      test "enqueues business transition to volume job" do
        as @staff_user
        @business.customer.update!(metered_plan: true)
        assert_enqueued_jobs 1, only: Licensing::TransitionEnterpriseToVolumeLicensingJob do
          post "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model", params: { licensing_model: "volume" }
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"
      end

      test "schedules business transition to volume job for the future" do
        as @staff_user
        @business.customer.update!(metered_plan: true)
        assert_enqueued_jobs 0, only: Licensing::TransitionEnterpriseToVolumeLicensingJob do
          post "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model", params: { licensing_model: "volume", transition_date: Date.tomorrow }
        end
        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"

        transition = Licensing::LicensingModelTransition.find_by(customer: @business.customer)
        assert_equal T.must(transition).transition_date, Date.tomorrow
      end
    end

    context "DELETE /stafftools/enterprises/:slug/enterprise_licensing/cancel_transition/:transition_id" do
      test "404s for non-staff" do
        as @non_staff_user
        delete "/stafftools/enterprises/#{@business}/enterprise_licensing/cancel_transition/1"

        assert_response :not_found
      end

      test "cancels transition scheduled for the future" do
        transition = create(:licensing_licensing_model_transition, customer: @business.customer, transition_date: Date.tomorrow)

        as @staff_user
        delete "/stafftools/enterprises/#{@business}/enterprise_licensing/transition_licensing_model/#{transition.id}"

        assert_redirected_to "/stafftools/enterprises/#{@business}/enterprise_licensing"

        assert_equal transition.reload.status, "cancelled"
      end
    end
  end
end
