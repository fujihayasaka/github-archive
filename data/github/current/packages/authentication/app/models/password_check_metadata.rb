# typed: true
# frozen_string_literal: true

class PasswordCheckMetadata < BinData::Record

  T.unsafe(self).endian :big
  T.unsafe(self).uint32 :discovery_timestamp, initial_value: 0
  T.unsafe(self).uint32 :reserved_for_future_use0, value: 0 #ignored
  T.unsafe(self).uint64be :compromised_password_id, initial_value: 0

  attr_accessor :big
  attr_accessor :discovery_timestamp
  attr_accessor :compromised_password_id

  # As we start using these, update the range
  (1..8).each do |i|
    T.unsafe(self).uint32 "reserved_for_future_use#{i}", value: 0
  end

  # group the bits together so they don't get treated as bytes
  (1..10).each do |i|
    T.unsafe(self).bit1 "reserved_for_future_use_being_used#{i}", value: 0
  end

  T.unsafe(self).bit1 :exact_email_and_password_match
  (1..5).each do |i|
    T.unsafe(self).bit1 "reserved_bit#{i}", value: 0
  end

  def weak?
    self.discovery_timestamp != 0
  end

  def weak_password_past_expiration?
    weak? && self.discovery_timestamp < User::PasswordDependency::TIME_ALLOWED_BEFORE_BLOCK.ago.to_i
  end

  def exact_match?
    T.unsafe(self).exact_email_and_password_match == 1
  end

  def should_block?
    exact_match? || weak_password_past_expiration?
  end
end
