# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticationLimitTest < GitHub::TestCase
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
  end

  test "more than 10 failures from the same IP trigger :short_ip metric" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
    }

    9.times { refute AuthenticationLimit.at_any?(increment: true, **opts) }
    5.times { assert AuthenticationLimit.at_any?(increment: true, **opts) }
  end

  test "gracefully handles abnormal characters in username" do
    opts = {
      login: "\x00 \u2713\n",
    }

    4.times { refute AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(increment: true, **opts)
  end

  test "short user lockouts are instrumented" do
    events = subscribe "lockout.short_login"
    ip = Faker::Internet.ip_v4_address
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: ip,
      from: :test,
    }
    opts = {
      login: @user.login,
      from: :test,
      ip: ip,
    }

    5.times { AuthenticationLimit.at_any?(increment: true, **opts) }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "long user lockouts are instrumented" do
    events = subscribe "lockout.long_login"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: nil,
      from: :test,
    }
    opts = {
      login: @user.login,
      from: :test,
    }

    100.times { AuthenticationLimit.at_any?(increment: true, from: :test, **opts) }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "short IP lockouts are instrumented" do
    events = subscribe "lockout.short_ip"
    opts = {
      login: @user.login,
      ip: Faker::Internet.ip_v4_address,
    }
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: opts[:ip],
      from: :test,
    }

    10.times { AuthenticationLimit.at_any?(increment: true, from: :test, **opts) }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "Long IP lockouts are instrumented" do
    events = subscribe "lockout.long_ip"
    opts = {
      login: @user.login,
      ip: Faker::Internet.ip_v4_address,
    }
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @user.login,
      actor_id: @user.id,
      actor_ip: opts[:ip],
      from: :test,
    }

    200.times { AuthenticationLimit.at_any?(increment: true, from: :test, **opts) }

    assert event = events.pop, "an event was expected"
    assert_equal expected_payload, event.payload
  end

  test "Lockouts are reset and increment after expiration" do
    opts = {
      login: @user.login,
      from: :test
    }
    # Use short_login to validate
    Timecop.freeze do
      5.times { AuthenticationLimit.at_any?(increment: true, **opts) }
      assert AuthenticationLimit.at_any?(**opts)
      Timecop.travel(11.minutes.from_now) do
        refute AuthenticationLimit.at_any?(**opts)
        5.times { AuthenticationLimit.at_any?(increment: true, **opts) }
        assert AuthenticationLimit.at_any?(**opts)
      end
    end
  end

  test "removing IP limit metric" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
    }

    10.times { AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(**opts)

    AuthenticationLimit.clear_data(opts.slice(:ip))

    refute AuthenticationLimit.at_any?(**opts)
  end

  test "removing auth limit metric" do
    opts = {
      login: "login_one",
    }

    5.times { AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(**opts)

    AuthenticationLimit.clear_data(opts.slice(:login))

    refute AuthenticationLimit.at_any?(**opts)
  end

  test "removing IP/auth limit metric" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
      login: "login_one",
    }

    10.times { AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(**opts)

    AuthenticationLimit.clear_data(opts.slice(:ip, :login))

    refute AuthenticationLimit.at_any?(**opts)
  end

  test "removing IP limit metric does not remove auth limit metric" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
      login: "login_one",
    }

    10.times { AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(**opts)

    assert AuthenticationLimit.at_any?(**opts.slice(:login))
    assert AuthenticationLimit.at_any?(**opts.slice(:ip))

    AuthenticationLimit.clear_data(opts.slice(:ip))

    assert AuthenticationLimit.at_any?(**opts.slice(:login))
    refute AuthenticationLimit.at_any?(**opts.slice(:ip))
  end

  test "removing auth limit metric does not remove IP limit metric" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
      login: "login_one",
    }

    10.times { AuthenticationLimit.at_any?(increment: true, **opts) }
    assert AuthenticationLimit.at_any?(**opts)

    assert AuthenticationLimit.at_any?(**opts.slice(:login))
    assert AuthenticationLimit.at_any?(**opts.slice(:ip))

    AuthenticationLimit.clear_data(opts.slice(:login))

    refute AuthenticationLimit.at_any?(**opts.slice(:login))
    assert AuthenticationLimit.at_any?(**opts.slice(:ip))
  end

  test "instruments remove" do
    events = subscribe "lockout.remove"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      limit_name: :short_login,
    }

    5.times { AuthenticationLimit.at_any?(increment: true, login: @user.login) }
    assert_equal true, AuthenticationLimit.at_any?(increment: false, login: @user.login)

    AuthenticationLimit.clear_data(login: @user.login)
    assert event = events.pop, "a lockout.remove event was expected"
    assert_equal expected_payload, event.payload
  end

  test "doesn't instrument without lockout" do
    events = subscribe "lockout.remove"

    2.times { AuthenticationLimit.at_any?(increment: true, login: @user.login) }
    AuthenticationLimit.clear_data(login: @user.login)

    assert_equal 0, events.size

  end

  test "whitelisted logins aren't limited" do
    login = "some_login"

    AuthenticationLimitAllowlistEntry.create!(
      metric: "login",
      value: login,
      creator: @user,
      expires_at: 10.days.from_now,
      note: "testing",
    )

    15.times { refute AuthenticationLimit.at_any?(increment: true, login: login) }
  end

  test "whitelisted ips aren't limited" do
    ip = Faker::Internet.ip_v4_address

    AuthenticationLimitAllowlistEntry.create!(
      metric: "ip",
      value: ip,
      creator: @user,
      expires_at: 10.days.from_now,
      note: "testing",
    )

    15.times { refute AuthenticationLimit.at_any?(increment: true, ip: ip,) }
  end

  test "web_ip limited when web IP lockouts are enabled" do
    ip = Faker::Internet.ip_v4_address
    9.times { AuthenticationLimit.at_any?(increment: true, web_ip: ip) }

    if GitHub.web_ip_lockouts_enabled?
      assert AuthenticationLimit.at_any?(increment: true, web_ip: ip)
    else
      refute AuthenticationLimit.at_any?(increment: true, web_ip: ip)
    end
  end

  test "whitelisted ips aren't limited for web_ip calls" do
    ip = Faker::Internet.ip_v4_address
    AuthenticationLimitAllowlistEntry.create!(
      metric: "ip",
      value: ip,
      creator: @user,
      expires_at: 10.days.from_now,
      note: "testing",
    )

    9.times { AuthenticationLimit.at_any?(increment: true, web_ip: ip) }

    # if GitHub.web_ip_lockouts_enabled?, we'd usually be at a limit here (see test above)
    # but since we've created a IP whitelist entry above, it should refute
    # if !GitHub.web_ip_lockouts_enabled?, we won't be at a limit regardless
    refute AuthenticationLimit.at_any?(increment: true, web_ip: ip)
  end

  test "whitelist not checked until over limit" do
    AuthenticationLimitAllowlistEntry.expects(:allowed?).never
    ip = Faker::Internet.ip_v4_address

    # Whitelist not checked until limit reached.
    9.times { refute AuthenticationLimit.at_any?(increment: true, ip: ip) }

    # Whitelist checked after limit reached.
    AuthenticationLimitAllowlistEntry.expects(:allowed?).once
    assert AuthenticationLimit.at_any?(increment: true, ip: ip)
  end

  test "no limit enforcement if KV is down" do
    opts = {
      ip: Faker::Internet.ip_v4_address,
    }

    result = GitHub::Result.new { raise GitHub::KV::UnavailableError }

    8.times { refute AuthenticationLimit.at_any?(increment: true, **opts) }
    # Bring KV down
    GitHub::Authentication::KV.store.stubs(:get).returns(result)
    GitHub::Authentication::KV.store.stubs(:increment).raises(GitHub::KV::UnavailableError)
    refute AuthenticationLimit.at_any?(increment: true, **opts)
    assert_equal 4, Failbot.reports.length
    Failbot.reports.each do |report|
      assert_equal "GitHub::KV::UnavailableError", Failbot.exception_classname_from_hash(report)
    end
    GitHub::Authentication::KV.store.unstub(:increment)
    GitHub::Authentication::KV.store.unstub(:get)
    # Bring KV back up
    # Ensure the last increment did nothing
    refute AuthenticationLimit.at_any?(increment: true, **opts)
    # Ensure incrementing worked since the DB was back up
    assert AuthenticationLimit.at_any?(increment: true, **opts)
  end
end
