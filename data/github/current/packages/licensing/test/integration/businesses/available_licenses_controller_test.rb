# typed: strict
# frozen_string_literal: true

require "test_helper"

class BusinessesAvailableLicensesControllerHttpTest < GitHub::IntegrationTestCase
  include BusinessTestHelpers


  skip_with_all_emus
  skip_enterprise

  fixtures do
    @user = T.let(create(:user), T.nilable(User))
    @member = T.let(create(:user), T.nilable(User))
    @owner = T.let(create(:user), T.nilable(User))
    org = create :organization, admins: [@member]
    @business = T.let(create(:business, seats: 10_000, owners: [@owner], organizations: [org]), T.nilable(Business))
  end

  context "GET /enterprises/:slug/available_licenses" do
    test_business_access do
      get "/enterprises/#{@business}/available_licenses"
    end

    test "renders available licenses" do
      as @owner
      get "/enterprises/#{@business}/available_licenses"
      assert_response :success
      assert_select "[data-test-selector=available-licenses]", text: "9,999"
    end
  end
end
