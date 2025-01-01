# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRateLimitallowlistingTest < GitHub::TestCase
  include AuditLogHelpers

  setup do
    @user = create(:user)
    @allowlister = create(:user)
  end

  teardown_once do
    disable_cache_storage
  end

  test "toggle allowlists a user" do
    @user.toggle_content_creation_rate_limit_allowlisted(allowlister: @allowlister)
    assert @user.content_creation_rate_limit_allowlisted?
  end

  test "toggle de-allowlists a user" do
    @user.content_creation_rate_limit_allowlist!(allowlister: @allowlister)
    @user.toggle_content_creation_rate_limit_allowlisted(allowlister: @allowlister)
    refute @user.reload.content_creation_rate_limit_allowlisted?
  end

  test "a user knows when they were allowlisted and by whom" do
    Timecop.freeze do
      @user.toggle_content_creation_rate_limit_allowlisted(allowlister: @allowlister)
      assert_equal Time.now.to_i, @user.content_creation_rate_limit_allowlisted_at.to_i
      assert_equal @allowlister, @user.content_creation_rate_limit_allowlister
    end
  end

  test "rate limit allowlists are audit logged" do
    events = subscribe "staff.rate_limit_allowlist"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @allowlister.login,
      actor_id: @allowlister.id,
      temporary: false,
    }
    @user.toggle_content_creation_rate_limit_allowlisted(allowlister: @allowlister)
    assert_equal expected_payload, events.pop.payload
  end

  test "a user can be temporarily allowlisted" do
    @user.temporarily_allowlist_content_creation(allowlister: @allowlister)
    assert @user.content_creation_rate_limit_allowlisted?
  end

  test "a user knows who temporarily allowlisted them, and when" do
    Timecop.freeze do
      @user.temporarily_allowlist_content_creation(allowlister: @allowlister)
      assert_equal Time.now.to_i, @user.temporary_content_creation_allowlisted_at.to_i
      assert_equal @allowlister, @user.temporary_content_creation_allowlisting_user
    end
  end

  test "temporary rate limit allowlists are audit logged" do
    events = subscribe "staff.rate_limit_allowlist"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @allowlister.login,
      actor_id: @allowlister.id,
      temporary: true,
    }
    @user.temporarily_allowlist_content_creation(allowlister: @allowlister)
    assert_equal expected_payload, events.pop.payload
  end

  test "de-allowlisting a user is audit logged" do
    events = subscribe "staff.rate_limit_deallowlist"
    expected_payload = {
      user: @user.login,
      user_id: @user.id,
      actor: @allowlister.login,
      actor_id: @allowlister.id,
    }
    @user.content_creation_rate_limit_deallowlist!(allowlister: @allowlister)
    assert_equal expected_payload, events.pop.payload
  end
end
