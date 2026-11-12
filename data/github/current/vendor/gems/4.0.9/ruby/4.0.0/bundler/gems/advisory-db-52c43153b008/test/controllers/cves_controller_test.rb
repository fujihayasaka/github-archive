# frozen_string_literal: true

require "test_helper"

class CVEsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    AdvisoryDB::Features.stubs(:enabled?).returns(false)
  end

  test "create reserves CVEs and redirects with success notice" do
    ReserveCVEJob.expects(:perform_now).with(force: true)

    post "/cves", headers: { "X-Okta-Username" => @user.email }

    assert_redirected_to cves_path
    assert_includes flash[:notice], "A request to reserve CVEs has been made"
  end

  test "create redirects with alert when CVE API client error occurs" do
    error_message = '{"error":"EXCEEDED_ID_QUOTA","message":"The amount requested would exceed the organization\'s ID quota."}'
    ReserveCVEJob.expects(:perform_now).with(force: true).raises(CVEAPI::Client::CVEAPIClientError, error_message)

    post "/cves", headers: { "X-Okta-Username" => @user.email }

    assert_redirected_to cves_path
    assert_includes flash[:alert], "Failed to reserve CVEs"
    assert_includes flash[:alert], "EXCEEDED_ID_QUOTA"
    assert_nil flash[:notice]
  end

  test "create redirects with alert when an unexpected error occurs" do
    ReserveCVEJob.expects(:perform_now).with(force: true).raises(StandardError, "something went wrong")

    post "/cves", headers: { "X-Okta-Username" => @user.email }

    assert_redirected_to cves_path
    assert_includes flash[:alert], "An unexpected error occurred while reserving CVEs"
    assert_includes flash[:alert], "something went wrong"
    assert_nil flash[:notice]
  end
end
