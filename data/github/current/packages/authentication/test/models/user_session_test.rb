# typed: true
# frozen_string_literal: true

require "test_helper"

class UserSessionModelTest < GitHub::TestCase
  include AuditLog::IntegrationTestHelpers
  include AuthenticationHelpers
  include GitHub::LoggerHelper
  include DogstatsTestHelpers
  include HydroTestHelpers

  fixtures do
    @user = create(:user, :established_sign_in_history)
    @user.sessions.destroy_all
  end

  setup do
    env = {
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_USER_AGENT" => "Rails Test",
      "HTTP_COOKIE" => "tz=UTC",
    }
    @request = new_request(env)
    @visitor = Analytics::Visitor.create
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    RedisRateLimiter::Result.any_instance.stubs(:at_limit?).returns(false)
    disable_feature_flag(:session_analysis_opt_out)
    enable_feature_flag(:session_analysis_revoke)
  end

  test "returns true for sign in records that are unrecognized", skip_unless: :sign_in_analysis_enabled? do
    refute_predicate create(:authentication_record, :unrecognized_device, user: @user).user_session, :anomalous?
  end

  test "creates a session with unrecognized status by default when user has no history", skip_unless: :sign_in_analysis_enabled? do
    assert_predicate create(:authentication_record).user_session, :anomalous?
  end

  test "generate new random key" do
    assert key = UserSession.random_key
    assert_equal 48, key.length
  end

  test "hash key" do
    key = "5YuBwJGAC95xXuRRAnICObB1nmO5fsM9mLGW_Ek7nIchg6jP"
    hashed_key = "FLom2MsyUdSG4OQJmI6YVZGWqh2WpJhl+wvtNlLZQZY="
    assert_equal hashed_key, UserSession.hash_key(key)
  end

  test "generate key pair" do
    key, hashed_key = UserSession.random_key_pair
    assert_equal 48, key.length
    assert_equal 44, hashed_key.length
    assert_equal hashed_key, UserSession.hash_key(key)
  end

  test "generate key pair for emu business", skip_unless: :dotcom_request? do
    business = create(:business, :enterprise_managed)
    key, hashed_key = UserSession.random_key_pair_with_business(business)
    assert_equal 57, key.length
    assert_equal 44, hashed_key.length
    assert_equal hashed_key, UserSession.hash_key(key)
  end

  test "authenticate against valid key" do
    base64_key, hashed_key = UserSession.random_key_pair
    session = create_session(hashed_key: hashed_key)

    authorized_session, authorized_key = UserSession.authenticate(base64_key)
    assert_equal session, authorized_session
    assert_equal base64_key, authorized_key
  end

  test "authenticate against valid key for emu business", skip_unless: :dotcom_request? do
    business = create(:business, :enterprise_managed)
    base64_key, hashed_key = UserSession.random_key_pair_with_business(business)
    session = create_session(hashed_key: hashed_key)

    authorized_session, authorized_key = UserSession.authenticate(base64_key)
    assert_equal session, authorized_session
    assert_equal base64_key, authorized_key
  end

  test "authenticate private mode against valid key" do
    base64_key, hashed_key = UserSession.random_key_pair
    session = create_session(hashed_private_mode_key: hashed_key)

    authorized_session, authorized_key = UserSession.authenticate_private_mode(base64_key)
    assert_equal session, authorized_session
    assert_equal base64_key, authorized_key

    # Private mode token doesn't work for normal auth
    refute UserSession.authenticate(base64_key)
  end

  test "generates a unique random value for hashed key" do
    session = new_session
    assert session.save
    assert session.hashed_key
    assert_equal 44, session.hashed_key.length
  end

  test "can not set hashed key to invalid characters" do
    session = new_session
    session.hashed_key = "LCa0a2j_xo/5m0U8HTBBNBNCLXBkg7-g+YpeiGJm564!"
    refute session.save
    assert session.errors[:hashed_key].any?
  end

  test "hashed key can be passed to constructor" do
    key, hashed_key = UserSession.random_key_pair

    session = new_session(hashed_key: hashed_key)
    assert session.save
    assert_equal hashed_key, session.hashed_key
  end

  test "hashed private mode key isn't initialized" do
    session = new_session
    assert session.save
    refute session.hashed_private_mode_key
  end

  test "can not set hashed private mode key to invalid characters" do
    session = new_session
    session.hashed_private_mode_key = "LCa0a2j_xo/5m0U8HTBBNBNCLXBkg7-g+YpeiGJm564!"
    refute session.save
    assert session.errors[:hashed_private_mode_key].any?
  end

  test "hashed private mode key can be passed to constructor" do
    key, hashed_key = UserSession.random_key_pair

    session = new_session(hashed_private_mode_key: hashed_key)
    assert session.save
    assert_equal hashed_key, session.hashed_private_mode_key
  end

  test "generates a secret for new session" do
    session = new_session
    assert session.save
    assert session.secret
    assert_equal 44, session.secret.length
  end

  test "generates a csrf token for new session" do
    session = new_session
    assert session.save
    assert session.csrf_token
    assert_equal 44, session.csrf_token.length
  end

  test "setting valid csrf token" do
    session = new_session
    session.csrf_token = "qmGQ8Gq3GBlyNzAQQFPkggG+uzP7I4s1/WAgJkoPB6c="
    assert session.save
  end

  test "setting invalid csrf token" do
    session = new_session
    session.csrf_token = "qmGQ8Gq3GBlyNzAQQFPkggG+uzP7I4s1/WAgJkoPB6c$"
    refute session.save
    assert session.errors[:csrf_token].any?
  end

  test "requires a user association" do
    session = new_session
    session.user = nil
    refute session.save
    assert session.errors[:user_id].any?
  end

  test "requires valid user association" do
    invalid_user_id = 6666
    refute User.find_by(id: invalid_user_id)

    session = new_session
    session.user_id = invalid_user_id
    refute session.save
    assert session.errors[:user_id].any?
  end

  test "user association cant be an organization" do
    session = new_session
    assert org = create(:organization)
    session.user = org
    refute session.save
    assert session.errors[:user_id].any?
  end

  test "user association cant be a bot" do
    session = new_session
    assert bot = create(:integration).bot
    session.user = bot
    refute session.save
    assert session.errors[:user_id].any?
  end

  test "impersonator user association with staff" do
    impersonator = create :staff_admin_user
    assert impersonator.site_admin?

    session = new_session
    session.impersonator_session = create(:user_session, user: impersonator)
    assert session.save
    assert session.impersonated?
  end

  test "impersonator user association must be staff" do
    impersonator = create(:user)
    refute impersonator.site_admin?

    session = new_session
    session.impersonator_session = create(:user_session, user: impersonator)
    refute session.save
    assert session.errors[:impersonator_id].any?
  end

  test "impersonator user association can't be self" do
    user = create :staff_admin_user
    assert user.site_admin?

    session = new_session
    session.user = user
    session.impersonator_session = create(:user_session, user: user)
    refute session.save
    assert session.errors[:impersonator_id].any?
  end

  test "impersonator user association must have session" do
    user = create :staff_admin_user
    assert user.site_admin?

    session = new_session
    session.user = user
    session.impersonator = user
    refute session.save
    assert session.errors[:impersonator_id].any?
  end

  test "impersonator user and session must match" do
    impersonator1 = create :staff_admin_user
    impersonator2 = create :staff_admin_user

    session = new_session
    session.impersonator = impersonator1
    session.impersonator_session = create(:user_session, user: impersonator2)
    refute session.save
    assert session.errors[:impersonator_id].any?
  end

  test "revoke" do
    events = subscribe "user_session.revoke"
    session = create_session
    assert session.active?
    refute session.revoked?

    session.revoke(:logout)
    refute session.active?
    assert session.revoked?

    assert event = events.pop, "an event was expected"

    payload = {
      user_session_id: session.id,
      user: session.user.login,
      user_id: session.user.id,
      reason: "logout"
    }

    assert_equal event.payload, payload
  end

  test "revoke session with reason" do
    session = create_session
    session.revoke(:logout)
    assert session.revoked?
    assert_equal "logout", session.revoked_reason
  end

  test "revoke raises an error with unknown reason" do
    session = create_session
    assert_raises ArgumentError do
      session.revoke(:no_good_reason)
    end
    refute session.revoked?
    assert_nil session.revoked_reason
  end

  test "revoke raises an error with no reason argument" do
    session = create_session
    assert_raises ArgumentError do
      session.revoke
    end
    refute session.revoked?
    assert_nil session.revoked_reason
  end

  test "revoke raises an error with with nil reason" do
    session = create_session
    assert_raises ArgumentError do
      session.revoke(nil)
    end
    refute session.revoked?
    assert_nil session.revoked_reason
  end

  test "revoke raises an error with with blank reason" do
    session = create_session
    assert_raises ArgumentError do
      session.revoke("")
    end
    refute session.revoked?
    assert_nil session.revoked_reason
  end

  test "impersonated session is revoked if parent is revoked" do
    impersonator = create :staff_admin_user
    impersonator_session = create(:user_session, user: impersonator)

    session = new_session
    session.impersonator_session = impersonator_session
    assert session.save

    refute impersonator_session.revoked?
    refute session.revoked?

    impersonator_session.revoke(:logout)

    assert impersonator_session.revoked?
    assert session.revoked?
  end

  test "impersonated session is revoked if parent is still valid" do
    impersonator = create :staff_admin_user
    impersonator_session = create(:user_session, user: impersonator)

    session = new_session
    session.impersonator_session = impersonator_session
    assert session.save

    refute impersonator_session.revoked?
    refute session.revoked?

    session.revoke(:logout)

    refute impersonator_session.revoked?
    assert session.revoked?
  end

  test "revoke all sessions" do
    UserSession.destroy_all
    session1 = create_session
    session2 = create_session
    session3 = create_session
    session3.revoke(:logout)

    count = UserSession.all.count
    assert_equal 3, count

    refute session1.revoked?
    assert_nil session1.revoked_reason
    refute session2.revoked?
    assert_nil session2.revoked_reason
    assert session3.revoked?
    assert_equal "logout", session3.revoked_reason

    count = UserSession.revoke_all(:security_incident)
    assert_equal 2, count

    session1.reload
    session2.reload
    session3.reload

    assert session1.revoked?
    assert_equal "security_incident", session1.revoked_reason
    assert session2.revoked?
    assert_equal "security_incident", session2.revoked_reason
    assert session3.revoked?
    assert_equal "logout", session3.revoked_reason
  end

  test "revoke all raises an error with with nil reason" do
    assert_raises ArgumentError do
      UserSession.revoke_all(nil)
    end
  end

  test "sets initial access timestamp" do
    session = new_session
    assert session.save
    assert_in_delta session.accessed_at.to_i, session.created_at.to_i, 1
  end

  test "sudo mode is enabled on creation" do
    session = new_session
    assert session.save

    assert session.sudo?
  end

  test "enable sudo mode" do
    session = new_session
    assert session.save

    session.expire_sudo
    refute session.sudo?

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
    }

    events = assert_performed_audit_entries(count: 1, only: "user_session.sudo") do
      session.enable_sudo
      assert session.sudo?
    end

    # audit logging
    assert_subset_hash expected_payload, events.first
  end

  test "sudo updates are throttled" do
    Timecop.freeze do
      creation = Time.now.to_i
      session = create_session

      assert_predicate session, :sudo?
      assert_equal creation, session.sudo_enabled_at.to_i

      # Doesn't bump if sudo_enabled_at == Time.now
      session.enable_sudo
      assert_predicate session, :sudo?
      assert_equal creation, session.sudo_enabled_at.to_i

      # Doesn't bump if sudo_enabled_at is less than SUDO_THROTTLING from now.
      Timecop.travel((UserSession::SUDO_THROTTLING / 2).seconds.from_now)
      session.enable_sudo
      assert_predicate session, :sudo?
      assert_equal creation, session.sudo_enabled_at.to_i

      # Bumps if sudo_enabled_at is greater than SUDO_THROTTLING from now.
      Timecop.travel(UserSession::SUDO_THROTTLING.from_now)
      session.enable_sudo
      assert_predicate session, :sudo?
      assert session.sudo_enabled_at.to_i > creation, "expected sudo_enabled_at to be bumped"
    end
  end

  test "impersonated sessions are always sudo" do
    impersonator = create :staff_admin_user

    session = new_session
    session.impersonator_session = create(:user_session, user: impersonator)
    assert session.save

    assert session.sudo?

    session.expire_sudo
    assert session.sudo?
  end

  test "impersonator session must be sudo" do
    impersonator = create :staff_admin_user
    impersonator_session = create(:user_session, user: impersonator)

    impersonator_session.expire_sudo
    refute impersonator_session.sudo?

    session = new_session
    session.impersonator_session = impersonator_session
    refute session.save
    assert session.errors[:impersonator_session_id].any?
  end

  test "always sudo when using cas auth" do
    with_auth_mode(:cas) do
      session = new_session
      assert session.save

      assert session.sudo?

      session.expire_sudo
      assert session.sudo?
    end
  end

  test "state" do
    session = create_session
    assert session.active?
    assert_equal :active, session.state

    session = create_session
    session.update_column :user_id, 0
    session.reload
    refute session.valid?
    assert_equal :invalid, session.state

    session = create_session
    session.revoke(:logout)
    session.reload
    assert_equal :revoked, session.state

    session = create_session
    session.update_column :accessed_at, Time.at(0)
    session.reload
    assert session.expired?
    assert_equal :expired, session.state
  end

  test "expires 2 weeks after initial access" do
    Timecop.freeze do
      session = create_session
      refute session.expired?

      Timecop.travel(1.week.from_now) do
        refute session.expired?
      end

      Timecop.travel(3.weeks.from_now) do
        assert session.expired?
      end
    end
  end

  test "expires 2 weeks after last access" do
    Timecop.freeze do
      session = create_session
      refute session.expired?

      Timecop.travel(1.week.from_now) do
        refute session.expired?
        assert session.access(@request)

        Timecop.travel(1.week.from_now) do
          refute session.expired?
        end

        Timecop.travel(3.weeks.from_now) do
          assert session.expired?
        end
      end
    end
  end

  test "expired on expires_at" do
    disable_feature_flag(:emu_user_session_expiration, @user)
    Timecop.freeze do
      session = create_session(expires_at: 2.hours.ago, accessed_at: 3.days.ago)
      refute session.expired?

      enable_feature_flag(:emu_user_session_expiration, @user)
      session.reload
      assert session.expired?
    end
  end

  test "expired scopes returns correct sessions" do
    Timecop.freeze do
      session1 = create_session(accessed_at: 1.week.ago)
      session2 = create_session(accessed_at: 3.days.ago, expires_at: 15.minutes.from_now)
      session3 = create_session(accessed_at: 3.weeks.ago)
      session4 = create_session(accessed_at: 1.week.ago, expires_at: 15.minutes.ago)

      assert_same_elements [session1, session2], @user.sessions.unexpired
      assert_same_elements [session3, session4], @user.sessions.expired
    end
  end

  test "expire_time" do
    Timecop.freeze do
      one_week_from_now = 1.week.from_now
      one_week_ago = 1.week.ago
      three_days_from_now = 3.days.from_now
      thirteen_days_ago = 13.days.ago
      one_day_from_now = 1.day.from_now

      session = create_session
      session.update_column :accessed_at, one_week_ago
      session.reload

      disable_feature_flag(:emu_user_session_expiration, @user)
      assert_equal one_week_from_now.to_s, session.expire_time.to_s

      session.update_column :expires_at, three_days_from_now
      session.reload
      assert_equal one_week_from_now.to_s, session.expire_time.to_s

      enable_feature_flag(:emu_user_session_expiration, @user)
      session.reload
      assert_equal three_days_from_now.to_s, session.expire_time.to_s

      session.update_column :accessed_at, thirteen_days_ago
      session.reload
      assert_equal one_day_from_now.to_s, session.expire_time.to_s
    end
  end

  test "can find previous session" do
    first_session = create_session
    assert_nil first_session.previous_user_session

    second_session = create_session
    assert_equal first_session, second_session.previous_user_session
  end

  test "ignores impersonated sessions when finding previous session" do
    first_session = create_session
    assert_nil first_session.previous_user_session

    impersonator = create :staff_admin_user
    impersonator_session = create(:user_session, user: impersonator)
    impersonated_session = create_session(impersonator_session: impersonator_session)
    assert_predicate impersonated_session, :impersonated?

    second_session = create_session
    assert_equal first_session, second_session.previous_user_session
  end

  test "access with request" do
    Timecop.freeze(Time.at(1542131343)) do
      session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
      assert session.access(@request)
      session.reload

      assert_equal "127.0.0.1", session.ip
      assert_equal "Rails Test", session.user_agent
      assert_equal "UTC", session.time_zone_name
      assert_in_delta Time.zone.now, session.accessed_at, 2
    end
  end

  test "access without request" do
    Timecop.freeze(Time.at(1542131343)) do
      session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 1.second)
      original_accessed_at = session.accessed_at
      assert session.access(@request)
      session.reload
      refute_equal original_accessed_at.to_i, session.accessed_at.to_i
      assert_in_delta Time.zone.now, session.accessed_at, 2
    end
  end

  test "access with request that doesn't change request attributes only updates accessed_at" do
    Timecop.freeze(Time.at(1542131343)) do
      session = create_session({
        accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes,
        in_use: true,
      })

      session.expects(:update_column).once
      session.expects(:save).never
      refute session.access(@request)
    end
  end

  test "access with request that does change request attributes updates entire record" do
    Timecop.freeze(Time.at(1542131343)) do
      session = create_session({
        accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes,
        ip: "1.2.3.4",
        in_use: true,
      })

      session.expects(:save).once
      session.expects(:update_column).never
      refute session.access(@request)
    end
  end

  test "updates session record when the IP address changes regardless of access throttling" do
    new_ip = "123.123.123.123"
    request = new_request({ "REMOTE_ADDR" => new_ip })

    session = create_session({
      accessed_at: UserSession.access_throttling.ago, # should be throttled
      updated_at: UserSession::IP_CHANGE_THROTTLING.ago - 1,
      ip: "1.2.3.4", # but IP change to 123.123.123.123 bypasses throttling
    })

    assert session.access(request)
    assert_equal new_ip, session.reload.ip
  end

  test "session sudo audit logging includes IP when present" do
    ip = "2.202.145.0"
    request = new_request({ "REMOTE_ADDR" => ip })
    GitHub::Location.stubs(:look_up).with(ip).returns({
      country_code: "US",
      country_name: "United States",
      region: "North East",
      region_name: "New Jersey",
      city: "Newark",
    })

    session = create_session({
      updated_at: Time.zone.now - UserSession.access_throttling - 5.minutes,
      ip: ip,
    })

    session.expire_sudo
    refute session.sudo?

    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor_ip: ip
    }

    events = assert_performed_audit_entries(count: 1, only: "user_session.sudo") do
      session.enable_sudo
      assert session.sudo?
    end

    # audit logging
    assert_subset_hash expected_payload, events.first
  end

  test "does not update session record when throttled on IP changes" do
    new_ip = "123.123.123.123"
    request = new_request({ "REMOTE_ADDR" => new_ip })

    session = create_session({
      updated_at: UserSession::IP_CHANGE_THROTTLING.ago - 1,
      ip: "1.2.3.4",
    })

    assert session.access(request)
    assert_equal new_ip, session.reload.ip

    new_ip = "123.123.123.100"
    request = new_request({ "REMOTE_ADDR" => new_ip })
    assert_no_difference %(GitHub.dogstats.increments("user_session").count) do
      refute session.access(request)
    end
    refute_equal new_ip, session.reload.ip
  end

  test "updates session record when IP throttle expires" do
    with_cache_enabled do
      throttle_window = UserSession::IP_CHANGE_THROTTLING + 1.minute
      new_ip = "123.123.123.123"
      request = new_request({ "REMOTE_ADDR" => new_ip })

      session = create_session({
        updated_at: throttle_window.ago,
        ip: "1.2.3.4",
      })

      Timecop.freeze do
        assert session.access(request)
        assert_equal new_ip, session.reload.ip
        assert GitHub.cache.get("v2:user_session:#{session.id}:update_ip")

        new_ip = "123.123.123.100"
        request = request = new_request({ "REMOTE_ADDR" => new_ip })

        GitHub.cache.delete("v2:user_session:#{session.id}:update_ip")
        Timecop.travel(throttle_window.from_now + 10) do
          assert session.access(request)
          assert_equal new_ip, session.reload.ip
          assert GitHub.cache.get("v2:user_session:#{session.id}:update_ip")
        end
      end
    end
  end

  test "access session with public X-Forwarded-For" do
    env = {
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "192.30.252.131",
      "HTTP_USER_AGENT" => "Rails Test",
      "HTTP_COOKIE" => "tz=UTC",
    }
    request = new_request(env)
    request.cookies[:_octo] = @visitor.octolytics_id

    session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
    assert session.access(request)

    assert_equal "192.30.252.131", session.ip
    assert_equal "Rails Test", session.user_agent
    assert_equal "UTC", session.time_zone_name
  end

  test "access session with private X-Forwarded-For" do
    env = {
      "REMOTE_ADDR" => "127.0.0.1",
      "HTTP_X_FORWARDED_FOR" => "192.168.1.1",
      "HTTP_USER_AGENT" => "Rails Test",
      "HTTP_COOKIE" => "tz=UTC",
    }
    request = new_request(env)
    request.cookies[:_octo] = @visitor.octolytics_id

    session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
    assert session.access(request)

    assert_equal "192.168.1.1", session.ip
    assert_equal "Rails Test", session.user_agent
    assert_equal "UTC", session.time_zone_name
  end

  test "access session with long user agent truncates it" do
    Timecop.freeze(Time.at(1542131343)) do
      user_agent = "Mozilla/4.0 (compatible; MSIE 7.0; Windows NT 6.1; WOW64; Trident/5.0; SLCC2; .NET CLR 2.0.50727; .NET CLR 3.5.30729; .NET CLR 3.0.30729; Media Center PC 6.0; InfoPath.3; .NET4.0C; .NET4.0E; MS-RTC LM 8; Microsoft Outlook 14.0.7109; ms-office; MSOffice 14)"
      request = new_request({ "REMOTE_ADDR" => Faker::Internet.ip_v4_address })
      request.headers["User-Agent"] = user_agent
      session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
      assert session.access(request)

      assert_equal user_agent[0...-1], session.user_agent
    end
  end

  test "access session scrubs non-ascii date from user agent" do
    Timecop.freeze(Time.at(1542131343)) do
      user_agent =
      request = new_request({ "REMOTE_ADDR" => Faker::Internet.ip_v4_address })
      request.headers["User-Agent"] = "Mozilla/5.0 (iPhone; CPU iPhone OS 5_0 like Mac OS X; ☃ edition)"
      session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
      assert session.access(request)

      assert_equal "Mozilla/5.0 (iPhone; CPU iPhone OS 5_0 like Mac OS X; ??? edition)", session.user_agent
    end
  end

  test "update timezone on user" do
    session = create_session(accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes)
    session.update_attribute(:time_zone_name, nil)

    user = session.user
    refute user.time_zone_name

    new_session.save
    assert session.access(@request)
    user.reload

    assert_equal "UTC", session.time_zone_name
    assert_equal "UTC", user.time_zone_name
  end

  context "mark_in_use" do
    test "access updates in_use" do
      session = create_session

      with_cache_enabled do
        Timecop.freeze do
          session.access(@request)
          assert session.reload.in_use

          GitHub.cache.get("v2:user_session:#{session.id}:update_in_use")
        end
      end

      assert_dogstats_increment 1, "account_switcher.user_session_in_use_on_access", tags: ["in_use:", "throttled:false"]
    end

    test "access not updated in_use when throttled" do
      session = create_session(in_use: false)

      with_cache_enabled do
        now = Time.now.utc
        Timecop.freeze now do
          session.access(@request)
          assert session.reload.in_use

          GitHub.cache.get("v2:user_session:#{session.id}:update_in_use")
        end

        session.in_use = false
        session.save

        pre_expiry = now + UserSession::IN_USE_THROTTLING - 1.second
        Timecop.freeze(pre_expiry) do
          session.access(@request)
          refute session.reload.in_use
        end

        assert_dogstats_increment 1, "account_switcher.user_session_in_use_on_access", tags: ["in_use:false", "throttled:false"]
        assert_dogstats_increment 1, "account_switcher.user_session_in_use_on_access", tags: ["in_use:false", "throttled:true"]
      end
    end

    test "access does not update in_use when already in use" do
      session = create_session(in_use: true)

      with_cache_enabled do
        session.access(@request)
        assert session.reload.in_use

        refute GitHub.cache.get("v2:user_session:#{session.id}:update_in_use")
      end

      assert_dogstats_increment 0, "account_switcher.user_session_in_use_on_access"
    end
  end

  test "recent" do
    Timecop.freeze do
      session = new_session
      assert session.save

      assert session.recent?

      Timecop.travel(1.day.from_now) do
        refute session.recent?
      end
    end
  end

  test "authenticate with key" do
    key, hashed_key = UserSession.random_key_pair
    session = create_session(hashed_key: hashed_key)

    authorized_session, authorized_key = UserSession.authenticate(key)
    assert_equal session, authorized_session
    assert_equal key, authorized_key

    refute UserSession.authenticate("A" * 48)
    refute UserSession.authenticate(nil)
    refute UserSession.authenticate("")
    refute UserSession.authenticate("123")
    refute UserSession.authenticate("=" * 80)
    refute UserSession.authenticate("\xD1\x9B\x86")
  end

  test "authenticate with key expires after 2 weeks" do
    Timecop.freeze do
      key, hashed_key = UserSession.random_key_pair
      session = create_session(hashed_key: hashed_key)

      assert UserSession.authenticate(key)

      Timecop.travel(1.week.from_now) do
        assert UserSession.authenticate(key)
      end

      Timecop.travel(3.weeks.from_now) do
        refute UserSession.authenticate(key)
      end
    end
  end

  test "authenticate with key expires 2 weeks after last access" do
    Timecop.freeze do
      key, hashed_key = UserSession.random_key_pair
      session = create_session(hashed_key: hashed_key)

      assert UserSession.authenticate(key)

      Timecop.travel(1.week.from_now) do
        assert UserSession.authenticate(key)
        assert session.access(@request)

        Timecop.travel(1.week.from_now - 1.second) do
          assert UserSession.authenticate(key)
        end

        Timecop.travel(3.weeks.from_now) do
          refute UserSession.authenticate(key)
        end
      end
    end
  end

  test "finding potentially compromised sessions" do
    UserSession.destroy_all
    session1 = create_session(created_at: 1.week.ago)
    session2 = create_session(created_at: Time.now)
    session3 = create_session(created_at: 1.week.ago)
    session3.revoke(:security_incident)
    session4 = create_session(created_at: 1.week.ago)
    session4.revoke(:logout)
    session5 = create_session(created_at: 1.week.ago)
    session5.update_column :accessed_at, 1.year.ago

    count = UserSession.all.count
    assert_equal 5, count

    sessions = UserSession.potentially_compromised(1.day.ago)
    assert_equal 1, sessions.count
    assert_equal session1.id, sessions.first.id
    assert session1.active?
  end

  test "revoke potentially compromised sessions" do
    UserSession.destroy_all
    session1 = create_session(created_at: 1.week.ago, accessed_at: 1.minute.ago)
    session2 = create_session(created_at: 1.week.ago, accessed_at: 1.week.ago)

    session3 = create_session(created_at: Time.now)
    session4 = create_session(created_at: 1.week.ago)
    session4.revoke(:security_incident)
    session5 = create_session(created_at: 1.week.ago)
    session5.revoke(:logout)
    session6 = create_session(created_at: 1.week.ago)
    session6.update_column :accessed_at, 1.year.ago

    count = UserSession.all.count
    assert_equal 6, count
    assert session1.active?
    assert session2.active?

    count = UserSession.potentially_compromised(1.day.ago).count
    assert_equal 2, count

    count = UserSession.revoke_potentially_compromised(1.day.ago, 1.hour)
    assert_equal 1, count

    session1.reload
    refute session1.revoked?

    session2.reload
    assert session2.revoked?
  end

  context "hydro" do
    include HydroTestHelpers
    test "sends user country change events to hydro", skip_enterprise: true do
      GitHub.stubs(:hydro_enabled?).returns(true)
      GitHub::Location.stubs(:look_up).with("136.22.4.67").returns(country_code: "DE")
      GitHub::Location.stubs(:look_up).with("2.202.145.0").returns({
        country_code: "US",
        country_name: "United States",
        region: "North East",
        region_name: "New Jersey",
        city: "Newark",
      })

      session = create_session({
        updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
        ip: "136.22.4.67",
      })

      last_location = GitHub::Location.look_up("136.22.4.67")

      # trigger ip_changed?
      request = new_request({ "REMOTE_ADDR" => "2.202.145.0" })
      assert session.access(request)

      expected_hydro_message = {
        actor: Hydro::EntitySerializer.user(session.user),
        previous_country_code: last_location[:country_code],
        previous_country_name: last_location[:country_name],
        previous_region: last_location[:region],
        previous_region_name: last_location[:region_name],
        previous_city: last_location[:city],
        anomalous_session: session.anomalous?,
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.UserCountryChange")
    end

    test "sends user session ip change events to hydro with timezone change" do
      old_ip = "136.22.4.67"
      new_ip = "2.202.145.0"
      GitHub.stubs(:hydro_enabled?).returns(true)
      GitHub::Location.stubs(:look_up).with(new_ip).returns({
        country_code: "DE",
        country_name: "Germany",
        region: "HH",
        region_name: "Hamburg",
        city: "Hamburg",
        postal_code: "20259",
        latitude: 53.5717,
        longitude: 9.9545,
      })
      GitHub::Location.stubs(:look_up).with(old_ip).returns({
        country_code: "US",
        country_name: "United States",
        region: "North East",
        region_name: "New Jersey",
        city: "Newark",
        latitude: 37.751,
        longitude: -97.822,
      })

      session = create_session({
        updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
        ip: old_ip,
        time_zone_name: "PST",
      })

      location = GitHub::Location.look_up(new_ip)
      last_location = GitHub::Location.look_up(old_ip)


      env = {
        "REMOTE_ADDR" => new_ip,
        "HTTP_COOKIE" => "tz=UTC",
      }
      request = new_request(env)
      assert session.access(request)

      expected_hydro_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(session.user),
        previous_ip: Hydro::EntitySerializer.ip_address(old_ip),
        current_ip: Hydro::EntitySerializer.ip_address(new_ip),
        previous_location:  Hydro::EntitySerializer.actor_location(last_location),
        current_location:  Hydro::EntitySerializer.actor_location(location),
        previous_timezone: "PST",
        current_timezone: "UTC",
        user_ids_for_device: [],
        user_logins_for_device: [],
        updated_at: session.updated_at,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.UserIPAddressUpdate")
    end

    test "reset memoized location on session ip change" do
      initial_ip = "1.2.3.4"
      old_ip = "136.22.4.67"
      new_ip = "2.202.145.0"
      GitHub.stubs(:hydro_enabled?).returns(true)
      GitHub::Location.stubs(:look_up).with(initial_ip).returns({})
      GitHub::Location.stubs(:look_up).with(old_ip).returns({
        country_code: "US",
        country_name: "United States",
        region: "North East",
        region_name: "New Jersey",
        city: "Newark",
        latitude: 37.751,
        longitude: -97.822,
      })
      GitHub::Location.stubs(:look_up).with(new_ip).returns({
        country_code: "DE",
        country_name: "Germany",
        region: "HH",
        region_name: "Hamburg",
        city: "Hamburg",
        postal_code: "20259",
        latitude: 53.5717,
        longitude: 9.9545,
      })

      session = create_session({
        updated_at: 10.days.ago,
        ip: initial_ip,
      })

      last_location = GitHub::Location.look_up(old_ip)
      location = GitHub::Location.look_up(new_ip)

      Timecop.travel(8.days.ago) do
        # trigger location change
        request = new_request({ "REMOTE_ADDR" => old_ip })
        assert session.access(request)
      end

      Timecop.travel(6.days.ago) do
        request = new_request({ "REMOTE_ADDR" => new_ip })
        assert session.access(request)
      end

      expected_hydro_message = {
        request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
        actor: Hydro::EntitySerializer.user(session.user),
        previous_ip: Hydro::EntitySerializer.ip_address(old_ip),
        current_ip: Hydro::EntitySerializer.ip_address(new_ip),
        previous_location:  Hydro::EntitySerializer.actor_location(last_location),
        current_location:  Hydro::EntitySerializer.actor_location(location),
        previous_timezone: "UTC",
        current_timezone: "UTC",
        user_ids_for_device: [],
        user_logins_for_device: [],
        updated_at: session.updated_at,
      }
      assert_hydro_published(expected_hydro_message, schema: "github.v1.UserIPAddressUpdate")
    end

    test "sends user session ip change events to hydro with device info", skip_unless: :sign_in_analysis_enabled? do
      Timecop.freeze do
        # ip change, but not necessarily the country change
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with(new_ip).returns(country_code: "CA", location: { lat: 1.0, lon: 1.0 })

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
        )

        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Rails Test", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        # the cookies/devices from the session surfer
        device_id = request.cookies["_device_id"] = AuthenticatedDevice.generate_id
        octo = request.cookies["_octo"] = Analytics::Visitor.create.octolytics_id
        shared_device_1 = create(:authenticated_device, device_id: device_id)
        shared_device_2 = create(:authenticated_device, device_id: device_id)

        assert session.access(request), "expected a session access event to happen"

        location = GitHub::Location.look_up(new_ip)
        last_location = GitHub::Location.look_up(old_ip)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(session.user),
          previous_ip: Hydro::EntitySerializer.ip_address(old_ip),
          current_ip: Hydro::EntitySerializer.ip_address(new_ip),
          previous_location:  Hydro::EntitySerializer.actor_location(last_location),
          current_location:  Hydro::EntitySerializer.actor_location(location),
          previous_timezone:  "UTC",
          current_timezone:  "UTC",
          user_ids_for_device: [shared_device_1.user.id, shared_device_2.user.id],
          user_logins_for_device: [shared_device_1.user.login, shared_device_2.user.login],
          previous_device_id: session.sign_in_record.authenticated_device.device_id,
          updated_at: session.updated_at,
        }
        assert_hydro_published(expected_hydro_message, schema: "github.v1.UserIPAddressUpdate")
      end
    end

    test "sends user session update events to hydro", skip_unless: :sign_in_analysis_enabled? do
      Timecop.freeze do
        # ip change, but not necessarily the country change
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with(new_ip).returns(country_code: "CA", location: { lat: 1.0, lon: 1.0 })

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36",
        )

        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/536.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        # the cookies/devices from the session surfer
        device_id = request.cookies["_device_id"] = AuthenticatedDevice.generate_id
        octo = request.cookies["_octo"] = Analytics::Visitor.create.octolytics_id
        shared_device_1 = create(:authenticated_device, device_id: device_id)
        shared_device_2 = create(:authenticated_device, device_id: device_id)

        assert session.access(request), "expected a session access event to happen"

        location = GitHub::Location.look_up(new_ip)
        last_location = GitHub::Location.look_up(old_ip)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(session.user),
          ip_change: true,
          country_change: false,
          timezone_change: false,
          device_id_change: true,
          user_agent_change: true,
          user_agent_mismatch: :BROWSER_VERSION,
          user_agent_change_risk: :LOW,
          user_agent_change_message: "Acceptable browser version change (Chrome:128 to Chrome:127)",
          user_ids_for_device: [shared_device_1.user.id, shared_device_2.user.id],
          user_logins_for_device: [shared_device_1.user.login, shared_device_2.user.login],
          previous_device_id: session.sign_in_record.authenticated_device.device_id,
          updated_at: session.updated_at,
          previous_accessed_at: session.accessed_at_before_last_save,
          revoke: false,
        }
        assert_hydro_published(expected_hydro_message, schema: "github.v1.UserSessionUpdate")
      end
    end
  end

  context "instrumentation" do
    test "instruments user_session.create event when session is created" do
      events = subscribe "user_session.create"
      session = create_session
      expected_payload = {
        user_session_id: session.id,
        user: session.user.login,
        user_id: session.user_id,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments user_session.access when session is created" do
      events = subscribe "user_session.access"
      session = create_session
      expected_payload = {
        user_session_id: session.id,
        user: session.user.login,
        user_id: session.user_id,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload
    end

    test "instruments user_session.access when last accessed outside of throttle limit window" do
      session = create_session
      events = subscribe "user_session.access"

      Timecop.freeze(UserSession.access_throttling.from_now) do
        assert session.access(@request)
      end

      expected_payload = {
        user_session_id: session.id,
        user: session.user.login,
        user_id: session.user_id,
      }

      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end

    test "does not instrument user_session.access when last accessed time is not within throttle limit window" do
      session = create_session
      events = subscribe "user_session.access"

      Timecop.freeze(UserSession.access_throttling.ago) do
        refute session.access(@request)
      end

      assert_nil events.pop, "an event was not expected"
    end
  end

  context "access risk analysis", skip_unless: :sign_in_analysis_enabled? do
    test "skip when exempt feature flag is enabled" do
      Timecop.freeze do
        # ip change, but not necessarily the country change
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with(new_ip).returns(country_code: "CA", location: { lat: 1.0, lon: 1.0 })

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        enable_feature_flag(:session_analysis_opt_out, session.user)

        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        refute_match "code.function=\"user_session.risk_analysis\"", output
      end
    end

    test "skip analysis when only accessed_at is touched" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"

        old_ip = "1.2.3.4"
        session = create(:user_session,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => old_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        refute_match "code.function=\"user_session.risk_analysis\"", output
        refute events.pop, "no event expected"
      end
    end

    test "skips risk log, skip audit log for no risk ip change" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"

        # ip change, but not necessarily the country change
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with(new_ip).returns(country_code: "CA", location: { lat: 1.0, lon: 1.0 })

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )


        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        refute_match "code.function=\"user_session.risk_analysis\"", output
        refute events.pop, "no event expected"
      end
    end

    test "log risk on no risk user_agent browser upgrade" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })

        session = create(:user_session,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/538.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"browser_version\"", output
        assert_match "gh.auth.session_update.risk=\"risk_none\"", output
        assert_match "gh.auth.session_update.message=\"Acceptable browser version change (Chrome:128 to Chrome:129)\"", output
        assert_match "gh.auth.session_update.ip_change=\"false\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"false\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_location: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: nil,
          associated_user_logins: nil,
          ip_change: false,
          timezone_change: false,
          country_change: false,
          user_agent_change: true,
          user_agent_mismatch: :browser_version,
          user_agent_change_risk: :risk_none,
          user_agent_change_message: "Acceptable browser version change (Chrome:128 to Chrome:129)",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "log risk on low_risk platform change" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })

        session = create(:user_session,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Safari/537.36"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/129.0.0.0 Mobile Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"platform\"", output
        assert_match "gh.auth.session_update.risk=\"low\"", output
        assert_match "gh.auth.session_update.message=\"Platform changed (Generic Linux:0 to Android:10)\"", output
        assert_match "gh.auth.session_update.ip_change=\"false\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"false\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_location: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: nil,
          associated_user_logins: nil,
          ip_change: false,
          timezone_change: false,
          country_change: false,
          user_agent_change: true,
          user_agent_mismatch: :platform,
          user_agent_change_risk: :low,
          user_agent_change_message: "Platform changed (Generic Linux:0 to Android:10)",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "log medium risk on normal platform change" do
      Timecop.freeze do
        old_ip = "1.2.3.4"
        new_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })

        session = create(:user_session,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Linux; Android 6.0; Nexus 5 Build/MRA58N) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"platform\"", output
        assert_match "gh.auth.session_update.risk=\"medium\"", output
        assert_match "gh.auth.session_update.message=\"Platform changed (macOS:10 to Android:6)\"", output
        assert_match "gh.auth.session_update.ip_change=\"false\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"false\"", output
      end
    end

    test "log low risk on chrome to safari to unknown swap" do
      Timecop.freeze do
        old_ip = "1.2.3.4"
        new_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })

        session = create(:user_session,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.1 Safari/605.1.15"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko)", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"browser\"", output
        assert_match "gh.auth.session_update.risk=\"low\"", output
        assert_match "gh.auth.session_update.message=\"Browser changed (Safari:18 to Unknown Browser:0)\"", output
        assert_match "gh.auth.session_update.ip_change=\"false\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"false\"", output
      end
    end

    test "log risk on low risk user_agent browser downgrade" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with(old_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with(new_ip).returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })

        session = create(:user_session,
          updated_at: Time.now - UserSession.access_throttling - 5.minutes,
          accessed_at: Time.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/127.0.0.0 Safari/536.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"browser_version\"", output
        assert_match "gh.auth.session_update.risk=\"low\"", output
        assert_match "gh.auth.session_update.message=\"Acceptable browser version change (Chrome:128 to Chrome:127)\"", output
        assert_match "gh.auth.session_update.ip_change=\"false\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"false\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_location: {
            country_code: "CA",
            location: { lat: 2.0, lon: 2.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: nil,
          associated_user_logins: nil,
          ip_change: false,
          timezone_change: false,
          country_change: false,
          user_agent_change: true,
          user_agent_mismatch: :browser_version,
          user_agent_change_risk: :low,
          user_agent_change_message: "Acceptable browser version change (Chrome:128 to Chrome:127)",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "log risk on country change" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )

        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"mismatch_none\"", output
        assert_match "gh.auth.session_update.risk=\"risk_none\"", output
        assert_match "gh.auth.session_update.message=\"No risk detected: user agent consistent\"", output
        assert_match "gh.auth.session_update.ip_change=\"true\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"true\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_location: {
            country_code: "US",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: [],
          associated_user_logins: [],
          ip_change: true,
          timezone_change: false,
          country_change: true,
          user_agent_change: false,
          user_agent_mismatch: :mismatch_none,
          user_agent_change_risk: :risk_none,
          user_agent_change_message: "No risk detected: user agent consistent",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "log high risk on country and browser agent change" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0"
        )
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => " Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"browser\"", output
        assert_match "gh.auth.session_update.risk=\"high\"", output
        assert_match "gh.auth.session_update.message=\"Browser changed (Firefox:131 to Safari:15)\"", output
        assert_match "gh.auth.session_update.ip_change=\"true\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"true\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_location: {
            country_code: "US",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: [],
          associated_user_logins: [],
          ip_change: true,
          timezone_change: false,
          country_change: true,
          user_agent_change: true,
          user_agent_mismatch: :browser,
          user_agent_change_risk: :high,
          user_agent_change_message: "Browser changed (Firefox:131 to Safari:15)",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "sends high risk user session update events to hydro", skip_unless: :sign_in_analysis_enabled? do
      Timecop.freeze do
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0"
        )

        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => " Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.4 Safari/605.1.15", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        # the cookies/devices from the session surfer
        device_id = request.cookies["_device_id"] = AuthenticatedDevice.generate_id
        octo = request.cookies["_octo"] = Analytics::Visitor.create.octolytics_id
        shared_device_1 = create(:authenticated_device, device_id: device_id)
        shared_device_2 = create(:authenticated_device, device_id: device_id)

        assert session.access(request), "expected a session access event to happen"

        location = GitHub::Location.look_up(new_ip)
        last_location = GitHub::Location.look_up(old_ip)

        expected_hydro_message = {
          request_context: Hydro::EntitySerializer.request_context(GitHub.context.to_hash),
          actor: Hydro::EntitySerializer.user(session.user),
          ip_change: true,
          country_change: true,
          timezone_change: false,
          device_id_change: true,
          user_agent_change: true,
          user_agent_mismatch: :BROWSER,
          user_agent_change_risk: :HIGH,
          user_agent_change_message: "Browser changed (Firefox:131 to Safari:15)",
          user_ids_for_device: [shared_device_1.user.id, shared_device_2.user.id],
          user_logins_for_device: [shared_device_1.user.login, shared_device_2.user.login],
          previous_device_id: session.sign_in_record.authenticated_device.device_id,
          updated_at: session.updated_at,
          previous_accessed_at: session.accessed_at_before_last_save,
          revoke: true,
        }
        assert_hydro_published(expected_hydro_message, schema: "github.v1.UserSessionUpdate")
      end
    end

    test "log medium platform risk on country and browser change when chrome to edge" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36 Edg/128.0.0.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        output = capture_logs do
          assert session.access(request), "expected a session access event to happen"
        end

        assert_match "code.function=\"user_session.risk_analysis\"", output
        assert_match "gh.auth.session_update.mismatch=\"platform\"", output
        assert_match "gh.auth.session_update.risk=\"medium\"", output
        assert_match "gh.auth.session_update.message=\"Platform changed (macOS:10 to Windows:10)\"", output
        assert_match "gh.auth.session_update.ip_change=\"true\"", output
        assert_match "gh.auth.session_update.zone_change=\"false\"", output
        assert_match "gh.auth.session_update.country_change=\"true\"", output

        expected_payload = {
          actor_ip: session.ip,
          actor_ip_was: "1.2.3.4",
          actor_location_was: {
            country_code: "CA",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_location: {
            country_code: "US",
            location: { lat: 0.0, lon: 0.0 },
          },
          actor_timezone: "UTC",
          actor_timezone_was: "UTC",

          device_id_was: session.sign_in_record.authenticated_device.device_id,
          accessed_at_was: session.accessed_at_before_last_save,
          user_agent_was: session.user_agent_before_last_save,
          associated_user_ids: [],
          associated_user_logins: [],
          ip_change: true,
          timezone_change: false,
          country_change: true,
          user_agent_change: true,
          user_agent_mismatch: :platform,
          user_agent_change_risk: :medium,
          user_agent_change_message: "Platform changed (macOS:10 to Windows:10)",
          user_session_id: session.id,
          user: session.user.login,
          user_id: session.user.id,
          actor: session.user.login,
          actor_id: session.user.id
        }

        assert event = events.pop, "expected event"
        assert_equal expected_payload, event.payload
      end
    end

    test "high risk session & country change queues revoke job" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        assert_enqueued_jobs 1, only: RevokeCompromisedSessionJob do
          assert session.access(request), "expected a session access event to happen"
        end
      end
    end

    test "high risk session change with IP change does queue revoke job" do
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "CA")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        assert_enqueued_jobs 1, only: RevokeCompromisedSessionJob do
          assert session.access(request), "expected a session access event to happen"
        end
      end
    end

    test "high risk session change without IP change does queue revoke job with ff enabled" do
      enable_feature_flag(:session_analysis_expand_revoke)
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => old_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        assert_enqueued_jobs 1, only: RevokeCompromisedSessionJob do
          assert session.access(request), "expected a session access event to happen"
        end
      end
    end

    test "high risk session change without IP change doesn't queue revoke job with ff disabled" do
      disable_feature_flag(:session_analysis_expand_revoke)
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          accessed_at: Time.zone.now - UserSession.access_throttling - 5.minutes,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => old_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        assert_enqueued_jobs 0, only: RevokeCompromisedSessionJob do
          assert session.access(request), "expected a session access event to happen"
        end
      end
    end

    test "high risk session change without country change does queue revoke job when ff enabled" do
      enable_feature_flag(:session_analysis_expand_revoke)
      Timecop.freeze do
        events = subscribe "user_session.risk_assessment"
        old_ip = "1.2.3.4"
        new_ip = "123.123.123.123"
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "CA")

        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: old_ip,
          user_agent: "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/128.0.0.0 Safari/537.36"
        )
        request = new_request({ "REMOTE_ADDR" => new_ip, "HTTP_USER_AGENT" => "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:131.0) Gecko/20100101 Firefox/131.0", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        assert_enqueued_jobs 1, only: RevokeCompromisedSessionJob do
          assert session.access(request), "expected a session access event to happen"
        end
      end
    end
  end

  test "instruments user_session.country_change when the country changes for the session", skip_unless: :sign_in_analysis_enabled? do
    Timecop.freeze do
      # Check for instrumentation of country changed
      events = subscribe "user_session.country_change"

      GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA")
      GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "US")

      session = create_session({
        accessed_at: UserSession::IP_CHANGE_THROTTLING.ago,
        updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
        ip: "1.2.3.4",
      })

      # trigger ip_changed?
      request = new_request({ "REMOTE_ADDR" => "123.123.123.123" })
      assert session.access(request)

      expected_payload = {
        actor_ip: session.ip,
        actor_ip_was: "1.2.3.4",
        actor_location_was: {
          country_code: "CA",
          location: { lat: 0.0, lon: 0.0 },
        },
        actor_location: {
          country_code: "US",
          location: { lat: 0.0, lon: 0.0 },
        },
        actor_timezone: "UTC",
        actor_timezone_was: "UTC",
        device_id_was: nil,
        accessed_at_was: session.accessed_at_before_last_save,
        user_agent_was: "Rails Test",
        associated_user_ids: [],
        associated_user_logins: [],
        user_session_id: session.id,
        user: session.user.login,
        user_id: session.user_id,
        actor: session.user.login,
        actor_id: session.user.id,
      }

      assert event = events.pop, "expected event"
      assert_equal expected_payload, event.payload

      entry_data = event.payload.merge(action: "user_session.country_change")
      audit_entry = AuditLogEntry.new_from_hash(entry_data)
      refute_predicate audit_entry, :hidden_from_users?
    end
  end

  test "ip changes with invalid associated devices are logged", skip_unless: :sign_in_analysis_enabled? do
    Timecop.freeze do
      device_id = T.cast(nil, T.untyped)
      octo = T.cast(nil, T.untyped)
      shared_device_1 = T.cast(nil, T.untyped)
      shared_device_2 = T.cast(nil, T.untyped)
      session = T.cast(nil, T.untyped)

      output = capture_logs do
        session = create(:user_session,
          updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
          ip: "1.2.3.4",
        )
        # ip change, but not necessarily the country change
        GitHub::Location.stubs(:look_up).with("1.2.3.4").returns(country_code: "CA", location: { lat: 2.0, lon: 2.0 })
        GitHub::Location.stubs(:look_up).with("123.123.123.123").returns(country_code: "CA", location: { lat: 1.0, lon: 1.0 })

        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => "123.123.123.123", "HTTP_USER_AGENT" => "Rails Test", "HTTP_X_GITHUB_REQUEST_ID" => "test_id" })

        # the cookies/devices from the session surfer
        device_id = request.cookies["_device_id"] = AuthenticatedDevice.generate_id
        octo = request.cookies["_octo"] = Analytics::Visitor.create.octolytics_id
        shared_device_1 = create(:authenticated_device, device_id: device_id)
        shared_device_2 = create(:authenticated_device, device_id: device_id)

        assert session.access(request), "expected a session access event to happen"
      end

      assert_match "code.function=\"user_session.location_change\"", output
      assert_match "gh.auth.login=\"#{session.user.login}\"", output
      assert_match "gh.enduser.id=\"#{session.user.id}\"", output
      assert_match "gh.auth.ip=\"123.123.123.123\"", output
      assert_match "gh.auth.ip_was=\"1.2.3.4\"", output
      assert_includes output, "gh.auth.location=#{ { country_code: "CA", location: { lat: 1.0, lon: 1.0 } }.inspect.inspect }"
      assert_includes output, "gh.auth.location_was=#{ { country_code: "CA", location: { lat: 2.0, lon: 2.0 } }.inspect.inspect }"
      assert_match "gh.auth.associated_user.ids=\"[#{shared_device_1.user.id}, #{shared_device_2.user.id}]\"", output
      assert_match "gh.auth.device.id=\"#{device_id}\"", output
      assert_match "gh.auth.device.id_was=\"#{session.sign_in_record.authenticated_device.device_id}\"", output
      assert_match "gh.auth.session.id=\"#{session.id}\"", output
      assert_match "user_agent.original=\"Rails Test\"", output
      assert_match "gh.request_id=\"test_id\"", output
      assert_match "gh.auth.session.update_at_was=\"#{session.updated_at.utc.strftime('%Y-%m-%dT%H:%M:%S.%6NZ')}\"", output
      assert_match "http.client_id=\"#{Analytics::Visitor.with_octolytics_id(octo).unversioned_octolytics_id}\"", output
    end
  end

  test "ip changes with garbage cookies don't send garbage data", skip_unless: :sign_in_analysis_enabled? do
    Timecop.freeze do
      session = create(:user_session,
        updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
        ip: "1.2.3.4",
      )

      output = capture_logs do
        # trigger ip_changed?
        request = new_request({ "REMOTE_ADDR" => "123.123.123.123" })

        # garbage data
        device_id = request.cookies["_device_id"] = "abc123"
        octo = request.cookies["_octo"] = "mona lisa"
        assert session.access(request), "expected a session access event to happen"
      end

      expected_log = {
        "code.function": "user_session.location_change",
        "device.id_was": session.sign_in_record.authenticated_device.device_id,
        "session.id": session.id,
        "device.cookie": nil,
        "client_id": nil,
      }

      assert_match "code.function=\"user_session.location_change\"", output
      assert_match "device.id_was=\"#{session.sign_in_record.authenticated_device.device_id}\"", output
      assert_match "session.id=\"#{session.id}\"", output
      refute_match "device.cookie", output
      refute_match "client_id", output
    end
  end

  test "doesn't instrument user_session.country_change if country doesn't change", skip_unless: :sign_in_analysis_enabled? do
    events = subscribe "user_session.country_change"

    # trigger ip_changed?
    request = new_request({ "REMOTE_ADDR" => "123.123.123.123" })

    # return an access from the same country
    GitHub::Location.stubs(:look_up).returns(country_code: "US")
    session = create_session({
      updated_at: UserSession::IP_CHANGE_THROTTLING.ago,
      ip: "1.2.3.4",
    })

    assert session.access(request)

    refute events.pop, "no event expected"
  end

  private

  def new_session(attrs = {})
    attrs[:ip] ||= "127.0.0.1"
    attrs[:user_agent] ||= "Rails Test"
    attrs[:user] ||= @user
    build(:user_session, attrs)
  end

  # note: this does _not_ create authentication records. You must use the factory
  # to `create` instead of this changed build-and-save
  def create_session(attrs = {})
    new_session(attrs).tap do |session|
      session.save!
    end
  end

  def new_request(params)
    ActionDispatch::Request.new(params.merge({ "PATH_INFO" => "/", "REQUEST_METHOD" => "GET", "rack.input" => "" }))
  end
end
