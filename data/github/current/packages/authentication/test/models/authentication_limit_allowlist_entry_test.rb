# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticationLimitAllowlistEntryTest < GitHub::TestCase
  fixtures do
    @creator = create(:user)
    @valid_metrics = AuthenticationLimit.instances.map(&:data_key).uniq.map(&:to_s)
    @metric = @valid_metrics.first
    @allowlisted_value = "1.1.1.1"
    @non_allowlisted_value = "2.2.2.2"
    @expired_value = "3.3.3.3.3"

    @active = AuthenticationLimitAllowlistEntry.create!(
      creator: @creator,
      metric: @metric,
      value: @allowlisted_value,
      expires_at: 1.day.from_now,
      note: "foo",
    )

    @expired = AuthenticationLimitAllowlistEntry.create!(
      creator: @creator,
      metric: @metric,
      value: @expired_value,
      expires_at: 1.day.ago,
      note: "foo",
    )
  end

  test "active entries are allowed" do
    assert AuthenticationLimitAllowlistEntry.allowed?(@metric, @allowlisted_value)
  end

  test "other values aren't allowed" do
    refute AuthenticationLimitAllowlistEntry.allowed?(@metric, @non_allowlisted_value)
  end

  test "metric must match" do
    refute AuthenticationLimitAllowlistEntry.allowed?("wrong", @allowlisted_value)
  end

  test "expired entries aren't allowed" do
    refute AuthenticationLimitAllowlistEntry.allowed?(@metric, @expired_value)
  end

  test "correct values" do
    assert AuthenticationLimitAllowlistEntry.allowed?(@metric, @allowlisted_value)
    assert AuthenticationLimitAllowlistEntry.allowed?(@metric, @allowlisted_value)
    refute AuthenticationLimitAllowlistEntry.allowed?(@metric, @non_allowlisted_value)
    refute AuthenticationLimitAllowlistEntry.allowed?(@metric, @non_allowlisted_value)
  end

  test "belongs to user" do
    assert_equal @creator, @active.creator
  end

  test "creator required" do
    entry = AuthenticationLimitAllowlistEntry.create(
      metric: @metric,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "metric required" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "value required" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      metric: @metric,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "expires_at required" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      metric: @metric,
      value: SecureRandom.hex,
      note: "foo",
    )
    refute entry.valid?
  end

  test "note required" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      metric: @metric,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
    )
    refute entry.valid?
  end

  test "must have unique metric/value combo" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      metric: @metric,
      value: @allowlisted_value,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "must have a valid metric" do
    entry = AuthenticationLimitAllowlistEntry.create(
      creator: @creator,
      metric: "foo",
      value: @allowlisted_value,
      expires_at: 1.day.ago,
      note: "foo",
    )
    refute entry.valid?
  end
end
