# typed: strict
# frozen_string_literal: true

# This abstract module encapsulates behavior to redact Memex field values supported in GitHub Projects in Elasticsearch.
# This field-level redaction is used when aggregations including grouping, slicing, and charting can leak information.
#
# For now, this applies only to the parent_issue field since that field is aggregatable and the parent issue
# can be in a different repository than the project item's child issue.
#
# This is intended to be included in the specific MemexProjectColumn::Field::Base subclasses that support this behavior.
module MemexProjectColumn::Interface::Redactable
  extend T::Helpers
  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  # Returns true if the field is redactable (i.e., it can provide repository Ids to authorize).
  sig { overridable.returns(T::Boolean) }
  def redactable?
    false
  end

  # Returns the repository Id from the field metadata to check for authorization.
  # This method must be implemented by any field set to be redactable?
  sig { overridable.params(metadata: MemexProjectColumn::Interface::Groupable::Metadata).returns(Integer) }
  private def repository_id(metadata:)
    raise NotImplementedError
  end

  # Returns all repository Ids from the group/slice aggregation nodes to check for redactions.
  sig do
    params(
      nodes: T::Array[T.any(MemexProjectColumn::Interface::Groupable::Group, T::Hash[String, T.untyped])]
    )
    .returns(T::Array[Integer])
  end
  private def repo_ids_from_metadata(nodes:)
    return [] unless redactable?

    repo_ids = nodes.map do |node|
      metadata = node.is_a?(MemexProjectColumn::Interface::Groupable::Group) ? node.metadata : node["metadata"]
      next unless metadata
      repository_id(metadata:)
    end
    repo_ids.compact.uniq
  end

  # Redacts group/slice aggregation data if the corresponding repository Id is not authorized.
  sig do
    params(
      nodes: T::Array[T.any(MemexProjectColumn::Interface::Groupable::Group, T::Hash[String, T.untyped])],
      unauthorized_repo_ids: T::Array[Integer]
    )
    .void
  end
  private def redact_node_data!(nodes:, unauthorized_repo_ids:)
    return unless redactable?

    nodes.each do |node|
      metadata = node.is_a?(MemexProjectColumn::Interface::Groupable::Group) ? node.metadata : node["metadata"]
      next unless metadata
      repo_id = repository_id(metadata:)
      unauthorized = unauthorized_repo_ids.include?(repo_id)
      metadata.redact! if unauthorized
    end
  end
end
