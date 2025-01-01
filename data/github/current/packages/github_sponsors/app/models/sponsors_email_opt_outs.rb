# typed: strict
# frozen_string_literal: true

class SponsorsEmailOptOuts
  extend T::Sig

  BITMASK_POSITIONS = T.let({
    all: 0,
    new_sponsorships: 1,
    cancelled_sponsorships: 2,
    upgrade_notices: 3,
    goal_completed: 4,
    milestone_reached: 5,
    reached_match_cap: 6,
  }, T::Hash[Symbol, Integer])

  sig { returns(Integer) }
  attr_reader :bitmask

  sig { params(bitmask: T.nilable(Integer)).void }
  def initialize(bitmask:)
    @bitmask = T.let(bitmask || 0, Integer)
  end

  #  "all" is its own flag that can be flipped on and off to handle the "opt out of everything scenario"
  #
  #  With this approach where it is its own flag, the scenario of adding new emails is automatically covered.
  #  Otherwise this would require running a transition each time a new email is added to pre-populate the opt out
  #  for users who have chosen to opt out of everything
  sig { returns(T::Boolean) }
  def opted_out_of_all?
    opted_out_of?(:all)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_new_sponsorships?
    opted_out_of?(:new_sponsorships)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_cancelled_sponsorships?
    opted_out_of?(:cancelled_sponsorships)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_upgrade_notices?
    opted_out_of?(:upgrade_notices)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_goal_completed?
    opted_out_of?(:goal_completed)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_milestone_reached?
    opted_out_of?(:milestone_reached)
  end

  sig { returns(T::Boolean) }
  def opted_out_of_reached_match_cap?
    opted_out_of?(:reached_match_cap)
  end

  # Updates email opt outs to enable the given key
  sig { params(key: Symbol).void }
  def opt_out_of(key)
    @bitmask = bitmask_with(key)
  end

  # Updates email opt outs to disable the given key
  sig { params(key: Symbol).void }
  def remove_opt_out(key)
    @bitmask = bitmask_without(key)
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

  sig { params(key: Symbol).returns(T::Boolean) }
  def opted_out_of?(key)
    bit_on?(T.must(BITMASK_POSITIONS[key]))
  end
end
