# typed: strict
# frozen_string_literal: true

class SponsorsFeaturedSponsorshipsSettings
  extend T::Sig

  BITMASK_POSITIONS = T.let({
    enabled: 0,
    automatic: 1,
  }, T::Hash[Symbol, Integer])

  sig { returns(Integer) }
  attr_reader :bitmask

  sig { params(bitmask: T.nilable(Integer)).void }
  def initialize(bitmask:)
    @bitmask = T.let(bitmask || 0, Integer)
  end

  # Enables featured sponsorships
  sig { void }
  def enable
    @bitmask = bitmask_with(:enabled)
  end

  # Sets featured sponsorships to automatic selection
  sig { void }
  def automatic
    @bitmask = bitmask_with(:automatic)
  end

  # Returns if featured sponsorships is enabled
  sig { returns(T::Boolean) }
  def enabled?
    bit_on?(T.must(BITMASK_POSITIONS[:enabled]))
  end

  # Returns if featured sponsorships is set to automatic selection
  sig { returns(T::Boolean) }
  def automatic?
    bit_on?(T.must(BITMASK_POSITIONS[:automatic]))
  end

  private

  # Returns bitmask with the bit at the given key's position set to on.
  sig { params(key: Symbol).returns(Integer) }
  def bitmask_with(key)
    @bitmask | (1 << T.must(BITMASK_POSITIONS[key]))
  end

  # Returns bitmask with the bit at the given key's position set to off.
  sig { params(key: Symbol).returns(Integer) }
  def bitmask_without(key)
    @bitmask & ~(1 << T.must(BITMASK_POSITIONS[key]))
  end

  sig { params(position: Integer).returns(T::Boolean) }
  def bit_on?(position)
    @bitmask & (1 << position) > 0
  end
end
