# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingsEducationDeveloperPackApplicationsControllerHttpTest < GitHub::IntegrationTestCase
  include Education::DeveloperPackApplicationTestHelper

  skip_in_multitenant_mode

  fixtures do
    @user = create(:user)
  end

  setup do
    enable_feature_flag("education-dev-pack-application", @user)
    skip unless GitHub.runtime.dotcom?
  end

  context "GET show" do
    test "redirects to login page when logged out" do
      get "/settings/education/developer_pack_applications"

      assert_response :redirect, login_path(return_to: settings_education_developer_pack_applications_path)
    end

    test "renders a 404 when the user is not flagged into the feature" do
      disable_feature_flag("education-dev-pack-application", @user)

      as @user
      get "/settings/education/developer_pack_applications"

      assert_response :not_found
    end

    test "renders the first page of the form" do
      as @user

      get "/settings/education/developer_pack_applications"

      assert_response :ok
    end
  end

  context "POST create" do
    test "redirects to login page when logged out" do
      post "/settings/education/developer_pack_applications"

      assert_response :redirect, login_path(return_to: settings_education_developer_pack_applications_path)
    end

    test "renders a 404 when the user is not flagged into the feature" do
      disable_feature_flag("education-dev-pack-application", @user)

      as @user
      post "/settings/education/developer_pack_applications"

      assert_response :not_found
    end

    context "when the form is valid" do
      context "when the user is continuing an application" do
        test "it renders the form partial" do
          as @user
          post "/settings/education/developer_pack_applications", params: {
            dev_pack_form: default_form_values,
            continue: 1,
          }

          assert_response :ok
          assert_empty assigns(:all_memoized)[:form_errors]
        end
      end

      context "when the user is submitting an application" do
        context "when the processing is successful" do
          test "it redirects to the billing summary page with a proper flash message" do
            as @user
            post "/settings/education/developer_pack_applications", params: {
              dev_pack_form: default_form_values({ form_variant: "upload_proof_form" }),
              submission: 1,
            }

            assert_equal "Your application has been submitted.", flash[:notice]
            assert_response :redirect, settings_user_billing_path
          end
        end
      end
    end

    context "when the form is invalid" do
      test "it renders the form partial with errors" do
        as @user
        post "/settings/education/developer_pack_applications", params: {
          dev_pack_form: default_form_values({
            school_name: "",
            new_school: 1,
          }),
          continue: 1,
        }

        assert_response :ok
        refute_empty assigns(:all_memoized)[:form_errors]
      end
    end
  end
end
