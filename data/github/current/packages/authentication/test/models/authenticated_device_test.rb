# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticatedDeviceTest < GitHub::TestCase
  include StringFromBinaryTestHelper
  include ResiliencyHelpers

  fixtures do
    @user = create(:user)
  end

  setup do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
  end

  test "can be created" do
    create(:authenticated_device)
  end

  test "does not allow nil device_ids" do
    assert_raises ActiveRecord::RecordInvalid do
      create(:authenticated_device, device_id: nil)
    end
  end

  test "does not allow bogus device_ids" do
    assert_raises ActiveRecord::RecordInvalid do
      create(:authenticated_device, device_id: "not hex")
    end
  end

  test "does not allow duplicate device_ids for a given user" do
    duplicate_id = create(:authenticated_device, user: @user).device_id
    assert_raises ActiveRecord::RecordInvalid do
      create(:authenticated_device, user: @user, device_id: duplicate_id)
    end
  end

  test "allows duplicate device_ids for difference users" do
    duplicate_id = create(:authenticated_device, user: create(:user)).device_id
    create(:authenticated_device, user: create(:user), device_id: duplicate_id)
  end

  test "requires a user" do
    assert_raises ActiveRecord::RecordInvalid do
      create(:authenticated_device, user: nil)
    end
  end

  test "can be associated with multiple passkeys" do
    first_device, second_device, third_device = create_list(:trusted_device, 3, user: @user)
    authenticated_device = create(:authenticated_device, user: @user)

    authenticated_device.trusted_device_client_registrations.create!(trusted_device: first_device, user: @user)
    authenticated_device.trusted_device_client_registrations.create!(trusted_device: second_device, user: @user)
    authenticated_device.trusted_device_client_registrations.create!(trusted_device: third_device, user: @user)

    assert_same_elements [first_device, second_device, third_device], authenticated_device.trusted_devices
  end

  test "destroying a device also deletes its join table entry" do
    trusted_device = create(:trusted_device, user: @user)
    authenticated_device = create(:authenticated_device, :with_trusted_devices, registered_trusted_device: trusted_device, user: @user)
    assert_equal [authenticated_device], trusted_device.authenticated_devices_registered

    assert_difference "TrustedDeviceClientRegistration.count", -1 do
      authenticated_device.destroy!
    end

    assert_empty trusted_device.authenticated_devices_registered
  end

  context "#throttled_touch" do
    test "does not update `last_accessed_at` if it was recently updated" do
      Timecop.freeze do
        sign_in_record = create(:authentication_record)

        device = sign_in_record.authenticated_device
        last_accessed_at = device.accessed_at
        refute_nil last_accessed_at

        assert_no_queries { device.throttled_touch }
        assert_equal last_accessed_at, device.reload.accessed_at
      end
    end

    test "updates `last_accessed_at` if it was not recently updated" do
      Timecop.freeze do
        sign_in_record = create(:authentication_record)

        device = sign_in_record.authenticated_device
        last_accessed_at = device.accessed_at
        refute_nil last_accessed_at

        Timecop.travel(AuthenticatedDevice::ACCESS_THROTTLE.from_now + 1.minute)
        device.throttled_touch
        refute_equal last_accessed_at, device.reload.accessed_at
      end
    end

    test "fails gracefully when the database is not available" do
      Timecop.freeze do
        device = create(:authentication_record).authenticated_device

        Timecop.travel(AuthenticatedDevice::ACCESS_THROTTLE.from_now + 1.minute)
        prevent_connections_to(ApplicationRecord::Ballast) do
          assert_nothing_raised { device.throttled_touch }
        end
        assert_equal 1, GitHub.dogstats.increments("authenticated_device.throttled_touch.failed").count
      end
    end
  end

  test "revoking a session unverifies a device" do
    session = create(:authentication_record, user: @user).user_session
    device = session.sign_in_record.authenticated_device

    device.verify!(display_name: device.display_name)
    assert_predicate device, :verified?

    assert_difference 'GitHub.dogstats.increments("authenticated_device").count', 1 do
      session.revoke(:user_remote_revoke)
    end
    assert session.revoked_at

    device.reload
    refute_predicate device, :verified?
    assert_includes GitHub.dogstats.increments("authenticated_device").last.tags, "action:unverify"
  end

  test "logging out doesn't unverify a device" do
    session = create(:authentication_record, user: @user).user_session
    device = session.sign_in_record.authenticated_device

    device.verify!(display_name: device.display_name)
    assert_predicate device, :verified?

    assert_no_difference 'GitHub.dogstats.increments("authenticated_device").count' do
      session.revoke(:logout)
    end
    assert session.revoked_at

    device.reload
    assert_predicate device, :verified?
  end

  context "#find_device_or_create!" do
    test "handles duplicate key errors by trying again against the primary" do
      session = create(:authentication_record, user: @user).user_session
      device = session.sign_in_record.authenticated_device
      refute_nil device

      # nil simulates the race condition
      # first against the replicas
      AuthenticatedDevice.expects(:find_device).with(anything, anything, database_query_role: :reading).returns(nil)
      # trigger the second lookup
      AuthenticatedDevice.expects(:create_device!).raises(ActiveRecord::RecordNotUnique)
      # then against the primary
      AuthenticatedDevice.expects(:find_device).with(anything, anything, database_query_role: :writing).returns(device)

      assert_no_difference "AuthenticatedDevice.count" do
        assert_equal [false, device], AuthenticatedDevice.find_device_or_create!(session.user, device_id: device.device_id, display_name: "foo")
      end
    end

    test "returns the object without creating a new" do
      session = create(:authentication_record, user: @user).user_session
      device = session.sign_in_record.authenticated_device
      refute_nil device

      AuthenticatedDevice.expects(:create_device!).never

      assert_no_difference "AuthenticatedDevice.count" do
        assert_equal [false, device], AuthenticatedDevice.find_device_or_create!(session.user, device_id: device.device_id, display_name: "foo")
      end
    end

    test "creates unique devices" do
      session = create(:authentication_record, user: @user).user_session
      assert_difference "AuthenticatedDevice.count" do
        AuthenticatedDevice.find_device_or_create!(session.user, device_id: AuthenticatedDevice.generate_id, display_name: "foo")
      end
    end

    test "raises when devices can't be found or created for other reasons" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      assert_raises(ActiveRecord::RecordInvalid) do
        AuthenticatedDevice.find_device_or_create!(@user, device_id: "garbage", display_name: "foo")
      end
    end
  end

  context "#self.generated_display_name" do
    test "doesn't include OS version info" do
      user_agent = "Mozilla/5.0 (compatible; MSIE 9.0; AOL 9.7; AOLBuild 4343.19; Windows NT 6.1; WOW64; Trident/5.0; FunWebProducts)"
      assert_equal "Internet Explorer on Windows", AuthenticatedDevice.generated_display_name(Browser.new(user_agent))
    end

    test "doesn't say macintosh" do
      user_agent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_14_5) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/74.0.3729.169 Safari/537.36"
      assert_equal "Chrome on macOS", AuthenticatedDevice.generated_display_name(Browser.new(user_agent))
    end

    test "doesn't say X11" do
      user_agent = "Mozilla/5.0 (X11; HasCodingOs 1.0; Linux x64) AppleWebKit/637.36 (KHTML, like Gecko) Chrome/70.0.3112.101 Safari/637.36 HasBrowser/5.0"
      assert_equal "Chrome on Linux", AuthenticatedDevice.generated_display_name(Browser.new(user_agent))
    end

    test "doesn't say DOES IT TAKE WHATEVER I WANT HERE?@?!?!? hxxps://foo.bar/input-token-here" do
      user_agent = "Mozilla/5.0 (DOES IT TAKE WHATEVER I WANT HERE?@?!?!? hxxps://foo.bar/input-token-here)"
      assert_equal "Unknown Browser on Unknown", AuthenticatedDevice.generated_display_name(Browser.new(user_agent))
    end
  end

  context "#known_sign_in_profile?" do
    test "returns true for known events" do
      assert_empty @user.authentication_records
      session = create(:authentication_record, :unrecognized_device, user: @user).user_session
      device = session.sign_in_record.authenticated_device

      refute_empty session.authentication_records
      assert device
      refute_predicate device, :verified?
      assert_predicate device, :has_authenticated_events?
    end

    test "returns false if no events are known" do
      device = create(:authenticated_device)
      refute_predicate device, :has_authenticated_events?
    end

    test "2fa partial sign ins do not count" do
      device = create(:authenticated_device, user: @user)
      create(:authentication_record, :partial_2fa_authentication_record, user: @user, authenticated_device: device)
      refute_predicate device, :has_authenticated_events?
    end
  end

  test "supports emoji for display_name" do
    taco_truck = "taco truck 🌮"
    taco_truck2 = "taco truck \xF0\x9F\x8C\xAE"

    device = create(:authenticated_device, display_name: taco_truck)

    assert_multibyte_tracked_changes(device, :display_name, taco_truck, taco_truck2)
  end
end unless GitHub.enterprise? && !GitHub.sign_in_analysis_enabled?
