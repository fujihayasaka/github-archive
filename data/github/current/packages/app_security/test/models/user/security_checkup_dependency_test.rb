# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSecurityCheckupTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @user = create(:user)
  end

  context "#security_checkup_key" do
    test "returns key" do
      assert_equal @user.security_checkup_key, "user.security_checkup_completed_at.#{@user.id}"
    end
  end

  context "#force_security_checkup_key" do
    test "returns key" do
      assert_equal @user.force_security_checkup_key, "security-checkup-force:#{@user.id}"
    end
  end

  context "#security_checkup_completed" do
    test "sets KV" do
      Timecop.freeze(Time.new(2018, 7, 2).utc) do
        refute GitHub::Authentication::KV.store.get(@user.security_checkup_key).value { nil }.present?

        @user.security_checkup_completed

        assert_equal Time.new(2018, 7, 2).utc, Time.parse(GitHub::Authentication::KV.store.get(@user.security_checkup_key).value { nil })
      end
    end

    test "sets a second KV if choosing to update" do
      refute GitHub::Authentication::KV.store.get(@user.security_checkup_action_key).value { nil }.present?
      @user.security_checkup_completed("updated")

      assert GitHub::Authentication::KV.store.get(@user.security_checkup_action_key).value { nil }
    end
  end

  context "#security_checkup_postponed" do
    test "pushes back 1 week" do
      Timecop.travel(Time.new(2018, 1, 2).utc) do
        make_two_factor_credential(@user)
        @user.security_checkup_completed
      end

      Timecop.travel(Time.new(2018, 7, 2).utc) do
        assert @user.security_checkup_due?

        @user.security_checkup_postponed

        refute @user.security_checkup_due?
      end

      Timecop.travel(Time.new(2018, 7, 14).utc) do
        assert @user.security_checkup_due?
      end
    end
  end

  context "#security_checkup_due?" do
    test "returns false when user does not have a two factor credential" do
      refute @user.security_checkup_due?
    end

    test "returns true when checkup has yet to be viewed" do
      Timecop.travel(Time.new(2018, 1, 2).utc) do
        make_two_factor_credential(@user)
      end

      Timecop.travel(Time.new(2018, 7, 2).utc) do
        assert @user.security_checkup_due?
      end
    end

    test "returns true when checkup was viewed more than three months ago" do
      Timecop.travel(Time.new(2018, 1, 2).utc) do
        make_two_factor_credential(@user)
        @user.security_checkup_completed
      end

      Timecop.travel(Time.new(2018, 7, 2).utc) do
        assert @user.security_checkup_due?
      end
    end

    test "returns false when checkup has been viewed in the last 3 months" do
      Timecop.travel(Time.new(2018, 5, 2).utc) do
        make_two_factor_credential(@user)
        @user.security_checkup_completed
      end

      Timecop.travel(Time.new(2018, 7, 2).utc) do
        refute @user.security_checkup_due?
      end
    end

    test "returns false when two_factor_credential was created in the past week" do
      Timecop.travel(Time.new(2018, 7, 2).utc) do
        make_two_factor_credential(@user)
      end

      Timecop.travel(Time.new(2018, 7, 4).utc) do
        refute @user.security_checkup_due?
      end
    end

    test "returns true when force_security_checkup! called" do
      Timecop.freeze do
        make_two_factor_credential(@user)
        refute @user.security_checkup_due?
        assert_nil GitHub::Authentication::KV.store.get(@user.force_security_checkup_key).value { nil }

        @user.force_security_checkup!
        assert_equal GitHub::Authentication::KV.store.get(@user.force_security_checkup_key).value { nil }, "true"

        assert @user.security_checkup_due?
        # checking security_checkup_due? does not remove the force flag in KV
        assert_equal GitHub::Authentication::KV.store.get(@user.force_security_checkup_key).value { nil }, "true"

        @user.clear_force_security_checkup!
        assert_nil GitHub::Authentication::KV.store.get(@user.force_security_checkup_key).value { nil }
      end
    end
  end

  context "#instrument_security_checkup" do
    test "instruments event type" do
      events = subscribe "user.security_checkup_update_now"

      @user.instrument_security_checkup("update_now")

      assert event = events.pop, "expected an instrument user.security_checkup_update_now event"
      assert_equal "user.security_checkup_update_now", event.name
    end

    test "records event in dogstats" do
      GitHub.dogstats.expects(:increment).at_least_once
      GitHub.dogstats.expects(:increment).with("user.security_checkup", has_entry(:tags, ["action:update_now"]))

      @user.instrument_security_checkup("update_now")
    end
  end

  context "#recently_took_action_on_security_checkup?" do
    test "is false by default" do
      refute_predicate @user, :recently_took_action_on_security_checkup?
    end

    test "is true if the user has recently clicked 'update' on the securit checkup" do
      @user.security_checkup_completed("updated")
      assert_predicate @user, :recently_took_action_on_security_checkup?
    end
  end

  context "#recovery_codes_status" do
    test "returns nil when feature flag is disabled" do
      GitHub.flipper[:recovery_codes_last_viewed_details_via_audit_log].disable
      Failbot.expects(:report).never
      assert_nil @user.recovery_codes_status
    end

    test "returns nil when codes have not been viewed" do
      GitHub.flipper[:recovery_codes_last_viewed_details_via_audit_log].enable
      Failbot.expects(:report).never
      expected_query = {
        user_id: @user.id,
      }
      Audit::Driftwood::Query.expects(:new_2fa_user_query).with(expected_query).returns(stub(execute: stub(results: [])))
      assert_nil @user.recovery_codes_status
    end

    test "returns status based on single recovery codes event" do
      GitHub.flipper[:recovery_codes_last_viewed_details_via_audit_log].enable
      Failbot.expects(:report).never
      mock_created_at = 1638023298069
      expected_query = {
        user_id: @user.id,
      }
      Audit::Driftwood::Query.expects(:new_2fa_user_query).with(expected_query).returns(stub(execute: stub(results: [
        {
          "action": "user.two_factor_recovery_codes_downloaded",
          "created_at": mock_created_at,
        }
      ])))
      refute_nil @user.recovery_codes_status
      assert_equal "Downloaded", @user.recovery_codes_status[:action]
      assert_equal Time.at(mock_created_at / 1000).to_i, @user.recovery_codes_status[:created_at].to_i
    end

    test "returns status based on latest recovery codes event" do
      GitHub.flipper[:recovery_codes_last_viewed_details_via_audit_log].enable
      Failbot.expects(:report).never
      mock_downloaded_created_at = 1638023298069
      mock_viewed_created_at = 1638023298069
      expected_query = {
        user_id: @user.id,
      }
      Audit::Driftwood::Query.expects(:new_2fa_user_query).with(expected_query).returns(stub(execute: stub(results: [
        {
          "action": "user.two_factor_recovery_codes_viewed",
          "created_at": mock_viewed_created_at,
        },
        {
          "action": "user.two_factor_recovery_codes_downloaded",
          "created_at": mock_downloaded_created_at,
        },
      ])))
      refute_nil @user.recovery_codes_status
      assert_equal "Viewed", @user.recovery_codes_status[:action]
      assert_equal Time.at(mock_viewed_created_at / 1000).to_i, @user.recovery_codes_status[:created_at].to_i
    end
  end
end
