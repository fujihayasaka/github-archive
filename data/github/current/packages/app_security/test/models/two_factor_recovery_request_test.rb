# typed: true
# frozen_string_literal: true

require "test_helper"

class TwoFactorRecoveryRequestTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @user = create(:user, login: "user")
    @device = create(:verified_authenticated_device, user: @user)

    @unverified_device = create(:authenticated_device, user: @user)
    @verified_device = create(:verified_authenticated_device, user: @user)

    @public_key_for_user = create(:public_key, user: @user)

    @actor = create :user, login: "bossman"
    @actor_device = create(:verified_authenticated_device, user: @actor)

    @actor_public_key = create(:public_key, user: @actor)

    @staff = create(:staff_admin_user)

    @earlier = (Time.now - 3.days).freeze
  end

  context "#find_request" do
    test "returns same record when correct token provided" do
      first = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      second = TwoFactorRecoveryRequest.find_request(@user, @unverified_device)

      refute_nil first
      refute_nil second

      assert_equal first.id, second.id
    end

    test "returns nil if requesting device does not match stored value" do
      other_device = create(:authenticated_device, user: @user)

      @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      match = TwoFactorRecoveryRequest.find_request(@user, other_device)

      assert_nil match
    end
  end

  context "#find_for_staff_review" do
    test "does not return incomplete record" do
      @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_nil request
    end

    test "return completed record when required fields populated" do
      record = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
        authenticated_device: @verified_device,
        request_completed_at: Time.now,
      )

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal record.id, request.id
    end

    test "return approved record when reviewed by staff" do
      record = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
        authenticated_device: @verified_device,
        request_completed_at: Time.now - 5.hours,
        reviewer: @staff,
        approved_at: Time.now,
      )

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal record.id, request.id
    end

    test "return declined record when reviewed by staff" do
      record = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
        authenticated_device: @verified_device,
        request_completed_at: Time.now - 5.hours,
        reviewer: @staff,
        declined_at: Time.now,
      )

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal record.id, request.id
    end

    test "return latest when multiple completed records exist" do
      latest = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
        authenticated_device: @verified_device,
        request_completed_at: Time.now,
      )

      Timecop.freeze(@earlier) do
        @previous_request = @user.two_factor_recovery_requests.create(
          requesting_device: @verified_device,
          otp_verified: true,
          authenticated_device: @verified_device,
          request_completed_at: @earlier + 10.minutes,
        )
      end

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal latest.id, request.id
    end

    test "returns new completed request if previous declined record exist" do
      next_request = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
        authenticated_device: @verified_device,
        request_completed_at: Time.now,
      )

      Timecop.freeze(@earlier) do
        declined = @user.two_factor_recovery_requests.create(
          requesting_device: @verified_device,
          otp_verified: true,
          authenticated_device: @verified_device,
          request_completed_at: Time.now,
          reviewer: @staff,
          declined_at: Time.now,
        )
      end

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal next_request.id, request.id
    end

    test "skips incomplete new request if previous declined record exists" do
      next_request = @user.two_factor_recovery_requests.create(
        requesting_device: @verified_device,
        otp_verified: true,
      )

      Timecop.freeze(@earlier) do
        @declined = @user.two_factor_recovery_requests.create(
          requesting_device: @verified_device,
          otp_verified: true,
          authenticated_device: @verified_device,
          request_completed_at: Time.now,
          reviewer: @staff,
          declined_at: Time.now,
        )
      end

      request = TwoFactorRecoveryRequest.find_for_staff_review(@user)

      assert_equal @declined.id, request.id
    end
  end

  context "#one_business_day_ago" do
    test "returns 72.hours.ago when current day is weekend or monday" do
      Timecop.freeze do
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:saturday))
        assert_equal time, 72.hours.ago
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:sunday))
        assert_equal time, 72.hours.ago
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:monday))
        assert_equal time, 72.hours.ago
      end
    end

    test "returns 24.hours.ago when current day is tues-friday" do
      Timecop.freeze do
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:tuesday))
        assert_equal time, 24.hours.ago
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:wednesday))
        assert_equal time, 24.hours.ago
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:thursday))
        assert_equal time, 24.hours.ago
        time = TwoFactorRecoveryRequest.one_business_day_ago(Date.today.prev_occurring(:friday))
        assert_equal time, 24.hours.ago
      end
    end
  end

  context "#secondary_evidence_method" do
    test "returns authenticated device when set" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.authenticated_device = @device

      assert_equal "Authenticated device", request.secondary_evidence_method
    end

    test "returns public key when set" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.public_key = @public_key_for_user

      assert_equal "Public key", request.secondary_evidence_method
    end

    test "returns personal access token when set" do
      request = create(:completed_two_factor_recovery_request_token, user: @user)

      assert_equal "Personal access token", request.secondary_evidence_method
    end

    test "return nil by default" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      assert_nil request.secondary_evidence_method
    end
  end

  context "#review_state" do
    test "incomplete by default" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)
      refute request.otp_verified
      assert_nil request.authenticated_device
      assert_nil request.public_key
      assert_nil request.oauth_access

      assert_equal request.review_state, :incomplete
    end

    test "incomplete after only verifying OTP" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      assert_equal request.review_state, :incomplete
    end

    test "ready_for_review after verifying OTP and device" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.authenticated_device = @device

      assert_equal request.review_state, :ready_for_review
    end

    test "ready_for_review after verifying OTP and public key" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.public_key = @public_key_for_user

      assert_equal request.review_state, :ready_for_review
    end

    test "ready_for_review after filling OTP and personal access token with repo scope" do
      request = create(:completed_two_factor_recovery_request_token, user: @user)

      assert_equal request.review_state, :ready_for_review
    end

    test "ready_for_review when valid authenticated device set" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.update!(authenticated_device: @device)

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :ready_for_review
    end

    test "evidence_missing if authenticated device removed from database" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      verified_device = create(:verified_authenticated_device, user: @user)

      request.update!(authenticated_device: verified_device)

      AuthenticatedDevice.find_by(id: verified_device.id)&.destroy

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :evidence_missing
    end

    test "evidence_missing if authenticated device is unverified after creation" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      # attach a verified device to the request
      verified_device = create(:verified_authenticated_device, user: @user)
      request.update!(authenticated_device: verified_device)
      assert_equal request.review_state, :ready_for_review

      # unverify the authenticated device
      AuthenticatedDevice.find_by(id: verified_device.id)&.unverify
      updated = TwoFactorRecoveryRequest.find_by(id: request.id)
      assert_equal updated&.authenticated_device_id, verified_device.id
      assert_equal updated&.review_state, :evidence_missing
    end

    test "ready_for_review for valid public key" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      public_key_for_user = create(:public_key, user: @user)

      request.update!(public_key: public_key_for_user)

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :ready_for_review
    end

    test "evidence_missing if public key removed from database" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      public_key_for_user = create(:public_key, user: @user)

      request.update!(public_key: public_key_for_user)

      PublicKey.find_by(id: public_key_for_user.id)&.destroy

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :evidence_missing
    end

    test "ready_for_review for valid personal access token" do
      request = create(:completed_two_factor_recovery_request_token, user: @user)

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :ready_for_review
    end

    test "evidence_missing if personal access token removed from database" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      valid_oauth_access = create(:personal_token_oauth_access, user: @user, note: "tested removing token after use in recovery request", scopes: [:repo])

      request.update!(oauth_access: valid_oauth_access)

      OauthAccess.find_by(id: valid_oauth_access.id)&.destroy

      updated = TwoFactorRecoveryRequest.find_by(id: request.id)

      assert_equal updated&.review_state, :evidence_missing
    end
  end

  context "#valid?" do
    test "is false if user not provided" do
      request = TwoFactorRecoveryRequest.new

      refute request.valid?
    end

    test "is false if requesting device not provided" do
      request = TwoFactorRecoveryRequest.new(user: @user)

      refute request.valid?
    end

    test "is false if public key does not belong to user" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.public_key = @actor_public_key

      refute_nil request.errors[:requesting_device]
    end

    test "is false if authenticated device is not verified" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.authenticated_device = @unverified_device

      refute_nil request.errors[:authenticated_device]
    end

    test "is false if authenticated device belongs to other user" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device, otp_verified: true)

      request.authenticated_device = @actor_device

      refute_nil request.errors[:authenticated_device]
    end

    test "raises validation error when repo scope is not found on personal access token" do
      ex = assert_raises(ActiveRecord::RecordInvalid) do
        request = create(:two_factor_recovery_request, :personal_token_empty_scopes, user: @user)
      end

      assert_equal "Validation failed: Oauth access Access token is missing required 'repo' scope", ex.message
    end

    test "raises validation error when token is not a personal access token" do
      ex = assert_raises(ActiveRecord::RecordInvalid) do
        request = create(:two_factor_recovery_request, :not_personal_token_valid_scopes, user: @user)
      end

      assert_equal "Validation failed: Oauth access Access token is not a personal access token", ex.message
    end
  end

  context "#after_create_commit" do
    test "emits hydro event" do
      Timecop.freeze do
        @user.two_factor_recovery_requests.create(requesting_device: @device)
        assert_hydro_published({
          user: Hydro::EntitySerializer.user(@user),
          action_type: :REQUEST_STARTED,
          }, schema: "github.v1.TwoFactorRecoveryRequestChanged")
        assert_hydro_messages(count: 1, schema: "github.v1.TwoFactorRecoveryRequestChanged")
      end
    end unless GitHub.enterprise?

    test "emits audit log event with payload" do
      events = subscribe "two_factor_account_recovery.start"

      request = @user.two_factor_recovery_requests.create(requesting_device: @device, otp_verified: true)

      assert event = events.pop, "an event was expected"
      assert_equal "two_factor_account_recovery.start", event.name

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        two_factor_account_recovery_id: request.id,
        requesting_device: @device.display_name,
        requesting_device_id: @device.id,
      }

      assert_equal expected_payload, event.payload
    end
  end

  context "#mark_as_complete" do
    test "emits audit log event with payload" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @device, otp_verified: true)
      request.authenticated_device = @device

      events = subscribe "two_factor_account_recovery.complete"

      request.mark_as_complete!

      assert event = events.pop, "an event was expected"
      assert_equal "two_factor_account_recovery.complete", event.name

      expected_payload = {
        user: @user.login,
        user_id: @user.id,
        two_factor_account_recovery_id: request.id,
      }

      assert_equal expected_payload, event.payload
    end
  end

  context "#verify_otp and #unverify_otp" do
    test "verifies and saves otp_verified" do
      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: false,
        authenticated_device: @device,
      )
      refute request.otp_verified?

      request.verify_otp

      assert request.reload.otp_verified?
    end

    test "unverifies and saves otp_verified" do
      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: true,
        authenticated_device: @device,
      )
      assert request.otp_verified?

      request.unverify_otp

      refute request.reload.otp_verified?
    end
  end

  context "#approve" do
    test "updates record in database" do
      create(:two_factor_credential, user: @user)

      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: true,
        authenticated_device: @device,
      )
      request.mark_as_complete!

      request.approve(@staff)

      after = @user.two_factor_recovery_requests.find(request.id)

      assert_equal after.reviewer, @staff
      refute_nil after.approved_at
    end

    test "can update record in database when evidence missing" do
      create(:two_factor_credential, user: @user)

      public_key_for_user = create(:public_key, user: @user)

      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: true,
        public_key: public_key_for_user,
      )

      request.mark_as_complete!

      PublicKey.find_by(id: public_key_for_user.id)&.destroy

      request.approve(@staff)

      after = @user.two_factor_recovery_requests.find(request.id)

      assert_equal after.reviewer, @staff
      refute_nil after.approved_at
    end

    test "sends mailer to continue with flow" do
      create(:two_factor_credential, user: @user)

      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: true,
        authenticated_device: @device,
      )
      request.mark_as_complete!

      AccountRecoveryMailer.expects(:request_approved_by_staff).
        once.
        with(@user, request.id, regexp_matches(/(A-Z0-9)*/), regexp_matches(/(A-Z0-9)*/), nil).
        returns(stub(deliver_later: nil))

      request.approve(@staff)
    end

    test "does not send mailer when request does not save successfully" do
      create(:two_factor_credential, user: @user)

      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        otp_verified: true,
        authenticated_device: @device,
      )
      request.mark_as_complete!

      request.expects(:update!).raises(ActiveRecord::RecordNotSaved)
      AccountRecoveryMailer.expects(:request_approved_by_staff).never

      begin
        request.approve(@staff)
      rescue ActiveRecord::RecordNotSaved
      end
    end

    test "fails if authenticated device has been unverified" do
      device = create(:verified_authenticated_device, user: @user)
      request = @user.two_factor_recovery_requests.create(
        requesting_device: device,
        otp_verified: true,
        authenticated_device: device,
      )
      request.mark_as_complete!

      device.unverify
      assert_raises do
        request.approve(@staff)
      end
    end
  end

  context "update" do
    test "requests with unauthenticated device can have review status updated" do
      request = @user.two_factor_recovery_requests.create(
        requesting_device: @device,
        authenticated_device: @unverified_device,
      )

      request.update!(staff_review_requested_at: Time.now)
      assert request.staff_review_requested_at.present?
    end
  end

  context "#hydro_evidence_type" do
    test "returns unknown by default" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      assert_equal request.hydro_evidence_type, :EVIDENCE_TYPE_UNKNOWN
    end

    test "returns :DEVICE when added" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      request.authenticated_device = @device

      assert_equal request.hydro_evidence_type, :DEVICE
    end

    test "returns :SSH_KEY when set" do
      request = @user.two_factor_recovery_requests.create(requesting_device: @unverified_device)

      request.public_key = @public_key_for_user

      assert_equal request.hydro_evidence_type, :SSH_KEY
    end

    test "returns :PERSONAL_ACCESS_TOKEN when set" do
      request = create(:completed_two_factor_recovery_request_token, user: @user)

      assert_equal request.hydro_evidence_type, :PERSONAL_ACCESS_TOKEN
    end
  end
end
