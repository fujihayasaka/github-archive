# typed: true
# frozen_string_literal: true

# Ruby's built-in sort is not stable. Sometimes that's fine, but sometimes you
# want to be sure that items with the same sort value stay in the same (pre-sorting)
# order after being sorted. If that's the case, StableSorter is for you.
#
#     Thing = Struct.new(:expected_position, :value)
#     things = [
#       Thing.new("fourth", 3),
#       Thing.new("first",  1),
#       Thing.new("second", 2),
#       Thing.new("third",  2)
#     ]
#
#     things.sort_by(&:value).map(&:expected_position)
#     => ["first", "third", "second", "fourth"]
#
#     StableSorter.new(things).sort_by(&:value).map(&:expected_position)
#     => ["first", "second", "third", "fourth"]

class StableSorter
  attr_reader :enum

  def initialize(enum)
    @enum = enum
  end

  def sort_by
    enum.sort_by.with_index { |e, i| [yield(e), i] }
  end
end
