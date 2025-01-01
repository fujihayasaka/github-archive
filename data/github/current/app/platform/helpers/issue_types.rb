# typed: strict
# frozen_string_literal: true

module Platform::Helpers::IssueTypes
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

  sig do
    params(
      id: String,
      context: Platform::Context,
    ).returns(T.nilable(IssueType))
  end
  def self.load_by_id(id, context)
    # To support the very unique permissioning of issue types, we need to load the issue type from ActiveRecord
    # instead of GraphQL auto-loading. This is because we have introduced new restrictions on issue types that
    # prevent them from being queried directly by non-org members. By loading manually, we skip those checks in
    # Platform::Objects::IssueType. These new permissions are typically handled by returning the new Platform::Models::IssueType
    # wrapper which contains additional issue / repository context. However, this is not possible here.
    return unless id.present?

    _, database_id = Platform::Helpers::NodeIdentification.from_global_id(id)
    issue_type = ::IssueType.find_by(id: database_id)

    raise Platform::Errors::NotFound, "Could not resolve to IssueType node with the global id of '#{id}'." unless issue_type

    issue_type
  end
end
