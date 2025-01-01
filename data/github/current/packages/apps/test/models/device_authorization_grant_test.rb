# typed: true
# frozen_string_literal: true

require "test_helper"

class DeviceAuthorizationGrantTest < GitHub::TestCase
  fixtures do
    @subject = create(:device_authorization_grant)
  end

  context "constants" do
    test "DEVICE_CODE_BYTES" do
      assert_equal 20, DeviceAuthorizationGrant::DEVICE_CODE_BYTES
    end

    test "USER_CODE_BYTES" do
      assert_equal 4, DeviceAuthorizationGrant::USER_CODE_BYTES
    end

    test "DEVICE_CODE_LAST_EIGHT_PATTERN" do
      assert_equal(/\A[a-f0-9]{8}\z/, DeviceAuthorizationGrant::DEVICE_CODE_LAST_EIGHT_PATTERN)
    end

    test "HASHED_DEVICE_CODE_PATTERN" do
      assert_equal(/\A[A-Za-z0-9+\/=]{44}\z/, DeviceAuthorizationGrant::HASHED_DEVICE_CODE_PATTERN)
    end

    test "USER_CODE_PATTERN" do
      assert_equal(/\A[A-Z0-9]{4}\-[A-Z0-9]{4}\z/, DeviceAuthorizationGrant::USER_CODE_PATTERN)
    end

    test "INTERVAL" do
      assert_equal 5, DeviceAuthorizationGrant::INTERVAL
    end

    test "EXPIRATION_WINDOW" do
      Timecop.freeze do
        assert_equal 15.minutes, DeviceAuthorizationGrant::EXPIRATION_WINDOW
      end
    end

    test "GRANT_TYPE" do
      assert_equal "urn:ietf:params:oauth:grant-type:device_code", DeviceAuthorizationGrant::GRANT_TYPE
    end

    test "VALID_APPLICATION_TYPES" do
      assert_equal %w(Integration OauthApplication), DeviceAuthorizationGrant::VALID_APPLICATION_TYPES
    end
  end

  context "initialization" do
    test "sets the expires_at before validation" do
      device_grant = build(:device_authorization_grant, application: @subject.application)
      assert_set_before_validation(device_grant, :expires_at)
    end

    test "sets the user_code before_validation" do
      device_grant = build(:device_authorization_grant, application: @subject.application)
      assert_set_before_validation(device_grant, :user_code)
    end
  end

  context "validation" do
    context "formatting" do
      test "device_code_last_eight" do
        new_device_code_last_eight = "ABCD@#$%"
        refute_match DeviceAuthorizationGrant::DEVICE_CODE_LAST_EIGHT_PATTERN, new_device_code_last_eight

        @subject.update(device_code_last_eight: "ABCD$%#?")
        refute_predicate @subject, :valid?
      end

      test "hashed_device_code" do
        new_hashed_device_code = "?" * 44
        refute_match DeviceAuthorizationGrant::HASHED_DEVICE_CODE_PATTERN, new_hashed_device_code

        @subject.update(hashed_device_code: new_hashed_device_code)
        refute_predicate @subject, :valid?
      end

      test "ip" do
        @subject.update(ip: nil)
        refute_predicate @subject, :valid?

        @subject.update(ip: ("a" * 41))
        refute_predicate @subject, :valid?
      end

      test "user_code" do
        new_user_code = "abcdef1234"
        refute_match DeviceAuthorizationGrant::USER_CODE_PATTERN, new_user_code

        @subject.update(user_code: new_user_code)
        refute_predicate @subject, :valid?
      end
    end

    context "presence" do
      test "requires an application" do
        @subject.update(application: nil)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:application], "must exist"
      end

      test "requires expires_at to be set" do
        @subject.update(expires_at: nil)

        refute_predicate @subject, :valid?
        assert_includes @subject.errors[:expires_at], "can't be blank"
      end

      test "requires the user_code be set on create" do
        DeviceAuthorizationGrant.any_instance.stubs(:initialize_user_code).returns(nil)
        device_grant = build(:device_authorization_grant, application: @subject.application)

        refute_predicate device_grant, :valid?
        assert_includes device_grant.errors[:user_code], "can't be blank"
      end

      test "allows user_code to be set to nil on update" do
        @subject.update(user_code: nil)
        assert_predicate @subject, :valid?
      end
    end
  end

  test ".hash_for" do
    code = "12345"
    assert_equal Digest::SHA256.base64digest(code), DeviceAuthorizationGrant.hash_for(code)
  end

  test ".unclaimed only finds records that don't have an oauth_access_id" do
    another_grant = create(:device_authorization_grant)
    another_grant.update(oauth_access: create(:oauth_access, application: another_grant.application))

    assert_nil @subject.oauth_access_id

    device_grants = DeviceAuthorizationGrant.unclaimed.where(id: [@subject.id, another_grant.id])
    assert_same_elements(device_grants, [@subject])
  end

  context "#claimed?" do
    test "returns true if the record has an oauth_access" do
      @subject.update(oauth_access: create(:oauth_access, application: @subject.application)); @subject.reload
      assert_predicate @subject, :claimed?
    end

    test "returns false if the record does not have an oauth_access" do
      assert_nil @subject.oauth_access
      refute_predicate @subject, :claimed?
    end
  end

  test "#expires_in returns the number of seconds until expiry" do
    Timecop.freeze do
      grant    = create(:device_authorization_grant)
      expected = (grant.expires_at - Time.zone.now).floor

      assert_equal expected, grant.expires_in
    end
  end

  context "expired?" do
    test "returns false if there is more time left" do
      Timecop.freeze do
        grant = create(:device_authorization_grant)

        assert_predicate grant.expires_in, :positive?
        refute_predicate grant, :expired?
      end
    end

    test "returns true if the record is expired" do
      Timecop.freeze(2.days.from_now) do
        assert_predicate @subject.expires_in, :negative?
        assert_predicate @subject, :expired?
      end
    end
  end

  test "integration_application_type?" do
    assert_equal "Integration", @subject.application_type
    assert_predicate @subject, :integration_application_type?
  end

  test "oauth_application_type?" do
    oauth_device_grant = create(:device_authorization_grant, application: create(:oauth_application))

    assert_equal "OauthApplication", oauth_device_grant.application_type
    assert_predicate oauth_device_grant, :oauth_application_type?
  end

  context "#redeem_device_code!" do
    test "updates a device grant and returns the unhashed code" do
      assert_nil @subject.hashed_device_code
      assert_nil @subject.device_code_last_eight

      device_code = @subject.redeem_device_code!
      @subject.reload

      assert_equal Digest::SHA256.base64digest(device_code), @subject.hashed_device_code
      assert_equal device_code.last(8), @subject.device_code_last_eight
    end

    test "raises a ActiveRecord::RecordInvalid if the fails to be set" do
      other_grant = create(:device_authorization_grant)
      device_code = other_grant.redeem_device_code!

      # Force the update to fail due to a uniquness constraint.
      SecureRandom.stubs(:hex).returns(device_code)

      assert_raises ActiveRecord::RecordInvalid do
        @subject.redeem_device_code!
      end
    end
  end

  test "#location returns the proper data based on IP" do
    GitHub::Location.stubs(:look_up).with("2.202.145.0").returns({
      country_code: "US",
      country_name: "United States",
      region: "North East",
      region_name: "New Jersey",
      city: "Newark",
    })

    @subject.update(ip: "2.202.145.0"); @subject.reload

    assert_same_hash({
      country_code: "US",
      country_name: "United States",
      region: "North East",
      region_name: "New Jersey",
      city: "Newark"
    }, @subject.location)
  end

  context "#scopes=" do
    test "cannot be set when the application_type is an Integration" do
      assert_predicate @subject, :integration_application_type?
      @subject.update(scopes: "repo")

      assert_predicate @subject, :valid?
      assert_nil @subject.scopes
    end

    test "can set be set as a string" do
      oauth_device_grant = create(:device_authorization_grant, application: create(:oauth_application))
      oauth_device_grant.update(scopes: "repo")

      assert_predicate oauth_device_grant, :valid?
      assert_same_elements ["repo"], oauth_device_grant.scopes
    end

    test "normalized scopes" do
      oauth_device_grant = create(:device_authorization_grant, application: create(:oauth_application))
      oauth_device_grant.update(scopes: %w[public_repo foo])

      assert_predicate oauth_device_grant, :valid?
      assert_same_elements ["public_repo"], oauth_device_grant.scopes
    end
  end

  test "#user is delegated to the OauthAccess" do
    access = create(:oauth_access, application: @subject.application)
    @subject.update(oauth_access: access); @subject.reload

    assert_equal access.user, @subject.user
  end

  private

  def assert_set_before_validation(subject, column)
    assert_nil subject.public_send(column)
    assert_predicate subject, :valid?

    refute_nil subject.public_send(column)
    refute_predicate subject, :persisted?
  end
end
