# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class GhesBackfillOauthAccessLastIssuedAtJobTest < GitHub::TestCase
  include AuditLogHelpers
  include JobTestHelper

  teardown_once do
    Elastomer::TestHelpers.delete_all
  end

  setup do
    Elastomer::TestHelpers.delete_all

    with_es_refresh do
      @new_access_created_at = 3.months.ago
      @regenerated_regenerated_at = 1.month.ago

      travel_to(@new_access_created_at.change(hour: 13, min: 15, sec: 20)) do
        @new_access_1 = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
      end

      travel_to(@new_access_created_at.change(hour: 13, min: 40, sec: 20)) do
        @new_access_2 = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
      end

      travel_to(@new_access_created_at.change(hour: 14, min: 40, sec: 20)) do
        @new_access_next_hour = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
      end

      destroyed = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
      destroyed.destroy_with_explanation(:web_user, entry_point: :test)

      travel_to((1.year + 1.day).ago) do
        @regenerated = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
        @old = create(:oauth_access, application_id: 0, application_type: "OauthApplication")
        @regenerated.reset_with_expiry(expires_at: Time.zone.now)
      end

      travel_to(@regenerated_regenerated_at.change(hour: 16, min: 32, sec: 13)) do
        @regenerated.reset_with_expiry(expires_at: Time.zone.now)
      end

      OauthAccess.update_all(last_issued_at: nil)
    end
  end

  test "updates last_issued_at for valid accesses" do
    refute Apps::KV.store.exists(GhesBackfillOauthAccessLastIssuedAtJob::BACKFILL_COMPLETED_KEY).value { false }

    GhesBackfillOauthAccessLastIssuedAtJob.perform_now

    assert Apps::KV.store.exists(GhesBackfillOauthAccessLastIssuedAtJob::BACKFILL_COMPLETED_KEY).value { false }
    assert_equal @new_access_created_at.change(hour: 13, min: 0, sec: 0), @new_access_1.reload.last_issued_at
    assert_equal @new_access_created_at.change(hour: 13, min: 0, sec: 0), @new_access_2.reload.last_issued_at
    assert_equal @new_access_created_at.change(hour: 14, min: 0, sec: 0), @new_access_next_hour.reload.last_issued_at
    assert_equal @regenerated_regenerated_at.change(hour: 16, min: 0, sec: 0), @regenerated.reload.last_issued_at
    assert_nil @old.reload.last_issued_at
  end
end if GitHub.enterprise?
