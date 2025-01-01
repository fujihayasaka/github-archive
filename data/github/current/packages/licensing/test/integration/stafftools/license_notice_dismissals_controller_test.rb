# typed: true
# frozen_string_literal: true

require "test_helper"

class StafftoolsLicenseNoticeDismissalsControllerHttpTest < GitHub::IntegrationTestCase
  fixtures do
    @staffer = create(:staff_admin_user)
  end

  context "POST #create" do
    test "dismisses license notice", enterprise_only: true do
      as @staffer
      post(
        "/stafftools/license_notice_dismissals",
        params: { ttl: "604800", type: "expiration" },
        xhr: true,
      )

      assert_response 200
    end
  end
end
