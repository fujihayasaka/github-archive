# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsBusinessesEnterpriseAgreementsControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @enterprise_agreement = create(:enterprise_agreement, seats: 100)
    @business = @enterprise_agreement.business
    @staff_admin_user = create(:staff_admin_user)
    @non_staff_user = create(:user)
  end

  if GitHub.single_business_environment?
    setup do
      as @staff_admin_user
    end

    context "GET /stafftools/enterprises/:slug/enterprise_agreements/new" do
      test "404s in a single business environment" do
        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/new"

        assert_response :not_found
      end
    end

    context "GET /stafftools/enterprises/:slug/enterprise_agreements/:id/edit" do
      test "404s in a single business environment" do
        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}/edit"

        assert_response :not_found
      end
    end

    context "POST /stafftools/enterprises/:slug/enterprise_agreements" do
      test "404s in a single business environment" do
        post "/stafftools/enterprises/#{@business.slug}/enterprise_agreements"

        assert_response :not_found
      end
    end

    context "PATCH /stafftools/enterprises/:slug/enterprise_agreements/:id" do
      test "404s in a single business environment" do
        patch "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}"

        assert_response :not_found
      end
    end
  else
    context "GET /stafftools/enterprises/:slug/enterprise_agreements/new" do
      test "404s for non-staff admins" do
        as @non_staff_user

        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/new"

        assert_response :not_found
      end

      test "renders the form to create an enterprise agreement for a business" do
        as @staff_admin_user

        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/new"

        assert_response :success
      end
    end

    context "GET /stafftools/enterprises/:slug/enterprise_agreements/:id/edit" do
      test "404s for non-staff admins" do
        as @non_staff_user

        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}/edit"

        assert_response :not_found
      end

      test "renders the form to update an enterprise agreement for a business" do
        as @staff_admin_user

        get "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}/edit"

        assert_response :success
      end
    end

    context "POST /stafftools/enterprises/:slug/enterprise_agreements" do
      test "404s for non-staff admins" do
        as @non_staff_user

        post "/stafftools/enterprises/#{@business.slug}/enterprise_agreements"

        assert_response :not_found
      end

      test "creates the new enterprise agreement and redirects to the business page" do
        as @staff_admin_user

        post "/stafftools/enterprises/#{@business.slug}/enterprise_agreements",
          params: { enterprise_agreement: attributes_for(:enterprise_agreement, agreement_id: "\t 333     ") }

        assert_redirected_to stafftools_enterprise_path(@business)
        assert_equal "333", @business.enterprise_agreements.last.agreement_id
      end

      test "renders the form and displays an error if there is a validation error (and doesn't create the agreement)" do
        as @staff_admin_user

        assert_no_changes "@business.enterprise_agreements.count" do
          post "/stafftools/enterprises/#{@business.slug}/enterprise_agreements",
            params: { enterprise_agreement: attributes_for(:enterprise_agreement, agreement_id: nil) }
        end

        assert_response :success
        assert_template :form
        assert_match /Failed/, flash[:error]
      end
    end

    context "PATCH /stafftools/enterprises/:slug/enterprise_agreements/:id" do
      test "404s for non-staff admins" do
        as @non_staff_user

        patch "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}"

        assert_response :not_found
      end

      test "updates the enterprise agreement and redirects to the business page" do
        as @staff_admin_user

        patch "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}",
          params: { enterprise_agreement: attributes_for(:enterprise_agreement, agreement_id: "\t      333      ") }

        assert_redirected_to stafftools_enterprise_path(@business)
        assert_equal "333", @enterprise_agreement.reload.agreement_id
      end

      test "renders the form and displays an error if there is a validation error (and doesn't update the agreement)" do
        as @staff_admin_user

        patch "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}",
          params: { enterprise_agreement: attributes_for(:enterprise_agreement, agreement_id: nil, seats: 123) }

        assert_response :success
        assert_template :form
        assert_match /Failed/, flash[:error]
        assert_equal 100, @enterprise_agreement.seats
      end
    end

    context "DELETE /stafftools/enterprises/:slug/enterprise_agreements/:id" do
      test "404s for non-staff admins" do
        as @non_staff_user

        delete "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}"

        assert_response :not_found
      end

      test "deletes the enterprise agreement and redirects to the business page" do
        as @staff_admin_user

        assert_difference "Licensing::EnterpriseAgreement.count", -1 do
          delete "/stafftools/enterprises/#{@business.slug}/enterprise_agreements/#{@enterprise_agreement.id}"
        end

        assert_redirected_to stafftools_enterprise_path(@business)
      end
    end
  end
end
