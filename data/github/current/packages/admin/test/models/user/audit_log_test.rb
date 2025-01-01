# typed: true
# frozen_string_literal: true

require "test_helper"

class User::AuditLogSearchingTest < GitHub::TestCase
  include AuditLogHelpers

  fixtures do
    @spammer = create(:user, login: "spammer", spammy: true)
    @user = create(:user)
  end

  setup do
    @time = Time.parse "2013-12-10 03:47:48 -0700"

    @login_entry = {
      action: "user.login",
      actor: @spammer.login,
      actor_id: @spammer.id,
      user: @spammer.login,
      user_id: @spammer.id,
      data: { :two_factor => true, "email" => "evil@spam.com" },
      created_at: @time,
      actor_ip: "1.1.1.1",
    }

    with_es_refresh { log @login_entry }

    @login_entry = AuditLogEntry.new_from_hash @login_entry
  end

  test "find logins" do
    logins = @spammer.find_logins
    assert_equal 1, logins.size

    login = @spammer.find_logins.first
    assert_equal "user.login", login["action"]
    assert_equal @spammer.login, login["user"]
  end

  test "find login ip addresses" do
    ips = @spammer.find_login_ip_addresses
    assert_equal ["1.1.1.1"], ips
  end

  test "find audit_events" do
    events = @spammer.find_audit_events("user.login")
    assert_equal 1, events.size

    login = @spammer.find_logins.first
    assert_equal "user.login", login["action"]
    assert_equal @spammer.login, login["user"]
  end

  test "audit_log_query" do
    query = "(user_id:#{@user.id} OR actor_id:#{@user.id})"
    assert_equal query, @user.audit_log_query
  end

  test "recent abuse reports query" do
    Timecop.freeze(2016, 1, 15) do
      query = "data.reported_user_id:#{@user.id} action:user.report_abuse created_at:>#{(Time.now - 2.weeks).to_i}"
      assert_equal query, @user.recent_abuse_reports_query
    end
  end
end
