# typed: strict
# frozen_string_literal: true

module Platform::Helpers::IssueTypes
  extend T::Sig

  sig do
    params(
      issue_types: T::Array[IssueType],
      order_by: T.nilable(Platform::Inputs::IssueTypeOrder)
    ).returns(T::Array[IssueType])
  end
  def self.order(issue_types = [], order_by = nil)
    return Platform::ArrayWrapper.new([]) if issue_types.empty?

    return Platform::ArrayWrapper.new(issue_types) if order_by.nil?

    Platform::ArrayWrapper.new(self.sort(issue_types, order_by[:field], order_by[:direction]))
  end

  sig do
    params(
      issue_types: T::Array[IssueType],
      field: String,
      direction: String,
    ).returns(T::Array[IssueType])
  end
  def self.sort(issue_types, field, direction)
    issue_types.sort do |a, b|
      left, right = direction == "ASC" ? [a, b] : [b, a]

      left_value = left.read_attribute(field)
      right_value = right.read_attribute(field)

      # If we're comparing strings, then downcase them
      left_value = left_value.downcase if left_value.is_a?(String)
      right_value = right_value.downcase if right_value.is_a?(String)

      result = left_value <=> right_value
      # If the values are the same, fall back on the ID
      result.nonzero? ? result : left.id <=> (right.id || -1)
    end
  end
end
