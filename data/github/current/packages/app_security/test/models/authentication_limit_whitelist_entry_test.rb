# typed: true
# frozen_string_literal: true

require "test_helper"

class AuthenticationLimitWhitelistEntryTest < GitHub::TestCase
  fixtures do
    @creator = create(:user)
    @valid_metrics = AuthenticationLimit.instances.map(&:data_key).uniq.map(&:to_s)
    @metric = @valid_metrics.first
    @whitelisted_value = "1.1.1.1"
    @non_whitelisted_value = "2.2.2.2"
    @expired_value = "3.3.3.3.3"

    @active = AuthenticationLimitWhitelistEntry.create!(
      creator: @creator,
      metric: @metric,
      value: @whitelisted_value,
      expires_at: 1.day.from_now,
      note: "foo",
    )

    @expired = AuthenticationLimitWhitelistEntry.create!(
      creator: @creator,
      metric: @metric,
      value: @expired_value,
      expires_at: 1.day.ago,
      note: "foo",
    )
  end

  test "active entries are whitelisted" do
    assert AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @whitelisted_value)
  end

  test "other values aren't whitelisted" do
    refute AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @non_whitelisted_value)
  end

  test "metric must match" do
    refute AuthenticationLimitWhitelistEntry.whitelisted?("wrong", @whitelisted_value)
  end

  test "expired entries aren't whitelisted" do
    refute AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @expired_value)
  end

  test "correct values" do
    assert AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @whitelisted_value)
    assert AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @whitelisted_value)
    refute AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @non_whitelisted_value)
    refute AuthenticationLimitWhitelistEntry.whitelisted?(@metric, @non_whitelisted_value)
  end

  test "belongs to user" do
    assert_equal @creator, @active.creator
  end

  test "creator required" do
    entry = AuthenticationLimitWhitelistEntry.create(
      metric: @metric,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "metric required" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "value required" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      metric: @metric,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "expires_at required" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      metric: @metric,
      value: SecureRandom.hex,
      note: "foo",
    )
    refute entry.valid?
  end

  test "note required" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      metric: @metric,
      value: SecureRandom.hex,
      expires_at: 1.day.from_now,
    )
    refute entry.valid?
  end

  test "must have unique metric/value combo" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      metric: @metric,
      value: @whitelisted_value,
      expires_at: 1.day.from_now,
      note: "foo",
    )
    refute entry.valid?
  end

  test "must have a valid metric" do
    entry = AuthenticationLimitWhitelistEntry.create(
      creator: @creator,
      metric: "foo",
      value: @whitelisted_value,
      expires_at: 1.day.ago,
      note: "foo",
    )
    refute entry.valid?
  end
end
