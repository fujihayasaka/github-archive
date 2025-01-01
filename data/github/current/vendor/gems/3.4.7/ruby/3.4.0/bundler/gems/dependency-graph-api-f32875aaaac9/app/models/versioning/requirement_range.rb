# A RequirementRange represents a list of compound requirements. Requirements
# in the list are AND-ed together. For example, the requirement range
# `>= 2.0.0, <= 2.0.5` includes versions 2.0.0 - 2.0.5.
module Versioning
  class RequirementRange
    include Enumerable

    delegate :each, :empty?, :==, to: :requirements

    attr_reader :requirements

    def self.wildcard
      new([Requirement.wildcard])
    end

    def initialize(requirements)
      @requirements = requirements
    end

    def min_upper_bound
      sorted_by_upper_bound.first
    end

    def encoded
      Range.new(max_encoded_lower_bound, min_encoded_upper_bound)
    end

    def max_encoded_lower_bound
      compact.map(&:encoded_lower_bound).compact.max
    end

    def min_encoded_upper_bound
      compact.map(&:encoded_upper_bound).compact.min
    end

    def substitute_wildcard
      empty? ? RequirementRange.wildcard : self
    end

    def exact_version
      # if this requirement range has an exact version, give it
      if requirements.count == 1 && requirements.first.operator.exact?
        return requirements.first.requirement
      else
        return nil
      end
    end

    def overlap?(other)
      all? do |left|
        other.all? do |right|
          left.overlap?(right)
        end
      end
    end

    def contain?(other_range)
      return false unless overlap?(other_range)

      # In this context, multiple requirements are joined with "AND".
      # Every requirement on the left must be satisfied by at least one
      # range on the right.
      requirements.all? do |left|
        other_range.any? do |right|
          left.contain?(right)
        end
      end
    end

    def compact
      RequirementRange.new(requirements.compact)
    end

    private

    def sorted_by_upper_bound
      requirements.sort do |left, right|
        next 0 if !left.upper_bound? && !right.upper_bound?
        next 1 if !left.upper_bound?
        next -1 if !right.upper_bound?

        (left.upper_bound <=> right.upper_bound).nonzero? ||
          compare_operator(left.operator, right.operator)
      end
    end

    def compare_operator(left, right)
      ((left.inclusive? ? 1 : 0) <=> (right.inclusive? ? 1 : 0))
    end
  end
end
