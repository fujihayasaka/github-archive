# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticationRecordTest < GitHub::TestCase
  fixtures do
    @user = create(:user, :established_sign_in_history, :two_factor_enabled)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    disable_feature_flag(:verified_device_enforcement_opt_out)
    reset_monolith_redis_rate_limiter
  end

  test "does not expose unexpectected login events to user-facing audit log" do
    raw_entry = {
      actor: @user.login,
      actor_id: @user.id,
      user: @user.login,
      user_id: @user.id,
    }

    %w(
      user.sign_in_from_unrecognized_location
      user.correct_password_from_unrecognized_device
      user.correct_password_from_unrecognized_device_and_location
      user.correct_password_from_unrecognized_location
    ).each do |action|
      event = raw_entry.merge(action: action)
      entry = AuditLogEntry.new_from_hash event
      assert_predicate entry, :hidden_from_users?
    end
  end

  test "records without octolytics_ids are invalid" do
    assert_raises(ActiveRecord::RecordInvalid) do
      create(:authentication_record, octolytics_id: nil)
    end
  end

  test "records with invalid clients can't be saved" do
    assert_raises(ActiveRecord::RecordInvalid) do
      create(:authentication_record, client: :impersonation)
    end
  end

  %i(
    password_changed
    sign_up
    user_session
    web
  ).each do |client|
    test "considers #{client} valid history" do
      event = create(:authentication_record, client: client)
      assert_includes event.user.authentication_records.authenticated_events, event
    end
  end

  test "considers password_changed events as web_sign_ins" do
    event = create(:authentication_record, :password_changed_authentication_record)
    assert_includes event.user.authentication_records.web_sign_ins, event
  end

  test "does not consider two_factor_partial_sign_in as valid history" do
    event = create(:authentication_record, :partial_2fa_authentication_record)
    refute_includes event.user.authentication_records.authenticated_events, event
  end

  test "nil counts as a known location" do
    create(:authentication_record, user: @user, country_code: nil)
    assert_no_difference 'GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").count' do
      create(:authentication_record, user: @user, country_code: nil)
    end
  end

  test "new unrecognized records as a result of 2fa challenges kick off a follow up job" do
    assert_enqueued_with(job: PartialTwoFactorAuthenticationNotificationJob) do
      assert_difference 'GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").count' do
        create(:authentication_record, :partial_2fa_authentication_record, :unrecognized_location, user: @user)
      end
    end
  end

  test "new recognized records as a result of 2fa challenges do not kick off a follow up job" do
    authentication_record = create(:authentication_record, user: @user)
    assert_no_enqueued_jobs(only: PartialTwoFactorAuthenticationNotificationJob) do
      assert_no_difference 'GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").count' do
        create(:authentication_record, :partial_2fa_authentication_record, user: @user, octolytics_id: authentication_record.octolytics_id, authenticated_device: authentication_record.authenticated_device)
      end
    end
  end

  test "non-2FA records do not enqueue the partial authentication job" do
    user = create(:user)
    assert_no_enqueued_jobs(only: PartialTwoFactorAuthenticationNotificationJob) do
      assert_difference 'GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").count', 1 do
        create(:authentication_record, :unrecognized_location, user: user)
      end
    end
  end

  test "partial authentication job not queued until create transaction committed" do
    user = create(:user)
    assert_enqueued_with(job: PartialTwoFactorAuthenticationNotificationJob) do
      AuthenticationRecord.transaction do
        assert_no_enqueued_jobs(only: PartialTwoFactorAuthenticationNotificationJob) do
          create(:authentication_record, :partial_2fa_authentication_record, :unrecognized_location, user: @user)
        end
      end
    end
  end

  test "immediately associates successful 2fa logins with their partial login event" do
    full_sign_in = create(:authentication_record, user: @user)
    partial_sign_in = full_sign_in.associated_partial_sign_in

    refute_nil partial_sign_in.user_session_id
    assert_equal full_sign_in.user_session_id, partial_sign_in.user_session_id
  end

  if GitHub.rate_limiting_enabled?
    test "stats rate limited users" do
      with_cache_enabled do
        create(:authentication_record, :unrecognized_location, user: @user)
        assert_includes GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").last.tags, "rate_limited:false"

        # No email should send since we're rate limited
        assert_no_difference "ActionMailer::Base.deliveries.count" do
          create(:authentication_record, :unrecognized_location, user: @user)
        end

        assert_includes GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").last.tags, "rate_limited:true"
      end
    end
  end

  test "does not error if location is not passed in" do
    record = create(:authentication_record, location: {})
    assert_nil record.country_code
    assert_nil record.city
    assert_nil record.region_name
  end

  test "setting a location object populates the entire model location data" do
    location = {
      country_code: "VU",
      city: "Port Vila",
      region_name: "Efate",
    }
    record = create(:authentication_record, location: location)
    assert_equal "VU", record.country_code
    assert_equal "Port Vila", record.city
    assert_equal "Efate", record.region_name
  end

  test "does not truncate region name when it is equal to the max column size" do
    # it would be tough to find a region name that was exactly 64 characters
    # so I simply removed the last character from the region name
    location = {
      country_code: "MD",
      city: "Tiraspol",
      region_name: "Administrative-Territorial Units of the Left Bank of the Dnieste",
    }
    record = create(:authentication_record, location: location)
    assert_equal "MD", record.country_code
    assert_equal "Tiraspol", record.city
    assert_equal "Administrative-Territorial Units of the Left Bank of the Dnieste", record.region_name
  end

  test "truncates long region names" do
    location = {
      country_code: "MD",
      city: "Tiraspol",
      region_name: "Administrative-Territorial Units of the Left Bank of the Dniester",
    }
    record = create(:authentication_record, location: location)
    assert_equal "MD", record.country_code
    assert_equal "Tiraspol", record.city
    assert_equal "Administrative-Territorial Units of the Left Bank of the Dnieste", record.region_name
  end

  test "does not analyze password change events" do
    AuthenticationRecord.any_instance.expects(:unexpected_sign_in_reason).never
    assert_difference "AuthenticationRecord.count", 1 do
      create(:authentication_record, :password_changed_authentication_record, user: @user)
    end
  end

  test "does not analyze user session events" do
    AuthenticationRecord.any_instance.expects(:unexpected_sign_in_reason).never
    assert_difference "AuthenticationRecord.count", 1 do
      create(:authentication_record, :user_session_authentication_record, user: @user)
    end
  end

  test "doesn't alert on sign ins on employee unicorns" do
    GitHub.stubs(:employee_unicorn?).returns(true)

    assert_no_difference "ActionMailer::Base.deliveries.count" do
      assert_difference 'GitHub.dogstats.increments("account_security.authentication_records.unexpected_login").count', 2 do
        perform_enqueued_jobs(only: [AddToSearchIndexJob]) do
          create(:authentication_record, :unrecognized_location, user: @user)
        end
      end
    end
  end

  context "#known_device?" do
    test "is true when flagged_reason is nil" do
      auth_record = create(:authentication_record, user: @user)
      assert_nil auth_record.flagged_reason
      assert_predicate auth_record, :known_device?
    end

    test "is true when flagged_reason is unrecognized_location" do
      auth_record = create(:authentication_record, :unrecognized_location, user: @user)
      refute_nil auth_record.flagged_reason
      assert_predicate auth_record, :known_device?
    end

    [:unrecognized_device, :unrecognized_device_and_location].each do |flagged_reason|
      test "is false for #{flagged_reason}" do
        auth_record = create(:authentication_record, flagged_reason, user: @user)
        refute_nil auth_record.flagged_reason
        refute_predicate auth_record, :known_device?
      end
    end
  end

  context "#known_location?" do
    test "is true when flagged_reason is nil" do
      auth_record = create(:authentication_record, user: @user)
      assert_nil auth_record.flagged_reason
      assert_predicate auth_record, :known_location?
    end

    test "is true when flagged_reason is unrecognized_device" do
      auth_record = create(:authentication_record, :unrecognized_device, user: @user)
      refute_nil auth_record.flagged_reason
      assert_predicate auth_record, :known_location?
    end

    [:unrecognized_location, :unrecognized_device_and_location].each do |flagged_reason|
      test "is false for #{flagged_reason}" do
        auth_record = create(:authentication_record, flagged_reason, user: @user)
        refute_nil auth_record.flagged_reason
        refute_predicate auth_record, :known_location?
      end
    end
  end
end unless GitHub.enterprise? && !GitHub.sign_in_analysis_enabled?
