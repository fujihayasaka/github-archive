# typed: true
# frozen_string_literal: true

require "test_helper"

class SettingsEducationDeveloperPackApplicationsSchoolsControllerHttpTest < GitHub::IntegrationTestCase
  skip_in_multitenant_mode

  fixtures do
    @user = create(:user)
  end

  setup do
    enable_feature_flag("education-dev-pack-application", @user)
    skip unless GitHub.runtime.dotcom?
  end

  context "GET index" do
    test "redirects to login page when logged out" do
      get "/settings/education/developer_pack_applications/schools"

      assert_response :redirect, login_path(return_to: settings_education_developer_pack_applications_schools_path)
    end

    test "returns 404 when feature is disabled" do
      disable_feature_flag("education-dev-pack-application", @user)

      as @user
      get "/settings/education/developer_pack_applications/schools", params: { q: "foo" }

      assert_response :not_found
    end

    test "returns a 406 when the request is not xhr" do
      as @user
      get "/settings/education/developer_pack_applications/schools", params: { q: "foo" }

      assert_response :not_acceptable
    end

    test "returns a blank page when the query is too short" do
      as @user
      get "/settings/education/developer_pack_applications/schools", params: { q: "fo" }, xhr: true

      assert_response :ok
      assert_empty response.body
    end

    test "returns a list of schools" do
      FakeEducationServer.mock_response = {
        schools: [
          {
            school_id: 42,
            name: "testschool1",
          },
          {
            school_id: 43,
            name: "testschool2",
          },
        ],
      }

      as @user
      get "/settings/education/developer_pack_applications/schools", params: { q: "foo" }, xhr: true

      assert_response :ok
      assert_select "div.typeahead-result", count: 2
      assert_select "[data-selected-school-id=42]", text: "testschool1"
      assert_select "[data-selected-school-id=43]", text: "testschool2"
    end
  end
end
