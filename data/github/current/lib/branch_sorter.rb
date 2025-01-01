# typed: false
# frozen_string_literal: true

require "version_sorter"
require "set"

# Implements a sorting algorithm based on VersionSorter, but ensures that values
# starting with a number are sorted before those starting with an alphabetical character.
class BranchSorter
  include Enumerable

  def initialize(values, &transformer)
    @values = values
    @transformer = transformer
  end

  def each(&block)
    return to_enum(__method__) unless block_given?
    perform(:sort, values, &block)
  end

  def reverse_each(&block)
    return to_enum(__method__) unless block_given?
    perform(:rsort, values, &block)
  end

  def self.compare(left, right)
    if DIGITS.include?(left[0])
      if DIGITS.include?(right[0])
        VersionSorter.compare(left, right)
      else
        -1
      end
    else
      if DIGITS.include?(right[0])
        1
      else
        VersionSorter.compare(left, right)
      end
    end
  end

  private

  DIGITS = Set.new("0".."9")

  def digit?(value)
    DIGITS.include?(value[0])
  end

  def values
    @values.to_ary
  end

  def perform(sort_method, values, &block)
    if @transformer
      values_map = {}
      values_to_sort = values.map do |value|
        transformed = @transformer.call(value)
        values_map[transformed] = value
        transformed
      end
      VersionSorter.send(:"#{sort_method}!", values_to_sort)
      post_sort(sort_method, values_to_sort) do |val|
        yield values_map.fetch(val)
      end
    else
      sorted_values = VersionSorter.send(sort_method, values)
      post_sort(sort_method, sorted_values, &block)
    end
  end

  def post_sort(sort_method, values, &block)
    numbers, words = values.partition(&method(:digit?))
    if sort_method == :sort
      numbers.each(&block)
      words.each(&block)
    else
      words.each(&block)
      numbers.each(&block)
    end
  end
end
