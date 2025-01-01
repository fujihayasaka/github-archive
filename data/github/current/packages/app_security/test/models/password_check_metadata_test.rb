# typed: true
# frozen_string_literal: true

require "test_helper"

class PasswordCheckMetadataTest < GitHub::TestCase
  test "is fixed length" do
    # 2 * 32-bit ints + 10 * (32-bit int + 1 bit)
    expected_length = 50
    check = PasswordCheckMetadata.new
    length = check.to_binary_s.length
    assert_equal expected_length, length

    time = Time.now.beginning_of_day.to_i
    check.discovery_timestamp = time
    assert_equal time, check.discovery_timestamp
    assert_equal expected_length, check.to_binary_s.length

    check.compromised_password_id = 123
    assert_equal 123, check.compromised_password_id
    assert_equal expected_length, check.to_binary_s.length

    T.unsafe(check).exact_email_and_password_match = 1
    assert_predicate check, :exact_email_and_password_match?
    assert_equal expected_length, check.to_binary_s.length
  end

  test "can be read" do
    metadata = PasswordCheckMetadata.new(
      discovery_timestamp: Time.now.beginning_of_day.to_i,
      compromised_password_id: 123,
      exact_email_and_password_match: 1,
    )

    to_binary_s = metadata.to_binary_s
    assert_equal metadata, PasswordCheckMetadata.new.read(to_binary_s)
  end

  test "sets values in constructor properly" do
    time = Time.now.beginning_of_day.to_i
    metadata = PasswordCheckMetadata.new(
      discovery_timestamp: time,
      compromised_password_id: 123,
      exact_email_and_password_match: 1,
    )

    assert_equal time, metadata.discovery_timestamp
    assert_equal 123, metadata.compromised_password_id
    assert_equal 1, T.unsafe(metadata).exact_email_and_password_match
  end

  test "has 8 extra byte fields and 5 extra bit fields for future use. setting the value has no effect" do
    metadata = PasswordCheckMetadata.new

    # Reserved bytes
    (0..8).each do |i|
      assert_equal 0, metadata.send("reserved_for_future_use#{i}")
      metadata.send("reserved_for_future_use#{i}=", 2)
      assert_equal 0, metadata.send("reserved_for_future_use#{i}")
    end

    # Padding after reserved bytes
    (1..10).each do |i|
      assert_equal 0, metadata.send("reserved_for_future_use_being_used#{i}")
      metadata.send("reserved_for_future_use_being_used#{i}=", 1)
      assert_equal 0, metadata.send("reserved_for_future_use_being_used#{i}")
    end

    # Reserved bits
    (1..5).each do |i|
      assert_equal 0, metadata.send("reserved_bit#{i}")
      metadata.send("reserved_bit#{i}=", 1)
      assert_equal 0, metadata.send("reserved_bit#{i}")
    end
  end
end
