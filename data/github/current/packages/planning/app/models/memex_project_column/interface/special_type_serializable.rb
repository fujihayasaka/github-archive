# typed: strict
# frozen_string_literal: true

# This module provides an interface for working with "special" field types: those that link existing data
# from elsewhere on GitHub, typically via the `content` association on a `MemexProjectItem`.
module MemexProjectColumn::Interface::SpecialTypeSerializable
  extend ActiveSupport::Concern
  extend T::Helpers

  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  class_methods do
    sig { returns(T::Boolean) }
    def special_type_serializable?
      true
    end
  end

  # Returns an object or array of objects that will be serialized for a field's value when a MemexProjectItem is
  # serialized for the client.
  #
  # A MemexProjectItem is serialized when rendering a MemexProject, a MemexProject returns paginated results,
  # is added to a MemexProject, or updated. A MemexProjectItem can also be serialized when it is being exported as CSV.
  #
  # Subclasses for special field types are expected to override this method to return an object or array of objects
  # implementing the MemexProjectColumn::Interface::Serializable interface.
  sig do
    overridable.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T.any(MemexProjectColumn::Interface::Serializable, T::Array[MemexProjectColumn::Interface::Serializable])))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: []); end

  sig do
    overridable.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T.any(MemexProjectColumn::Interface::Serializable::JSONValue, T::Array[MemexProjectColumn::Interface::Serializable::JSONValue])))
  end
  def json_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    case value
    when Array
      value.map(&:memex_column_hash)
    else
      value&.memex_column_hash
    end
  end

  sig do
    overridable.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(String))
  end
  def csv_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    case value
    when Array
      value.map(&:csv_column_value).join(", ")
    else
      value&.csv_column_value
    end
  end

  # This helper can be used in `Indexable#preload_elasticsearch_document` implementations to make sure that the
  # content association (and other associations rooted at content) has been preloaded prior to other preloads that
  # depend on it.
  #
  # EXAMPLE:
  #
  #   def preload_elasticsearch_document_data(items)
  #     preload_content_tree(items)                    # Make sure the content association has been preloaded
  #     issues = items.select(&:issue?).map(&:content) # Now we can map over content without making extra queries
  #     GitHub::PrefillAssociations.prefill_associations(issues, :assignees)
  #   end
  #
  sig { params(items: T::Array[MemexProjectItem]).void }
  private def preload_content_tree(items)
    GitHub::PrefillAssociations.prefill_associations(items, [:content, :repository]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    pull_requests = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    GitHub::PrefillAssociations.prefill_associations(pull_requests, :issue) # domain-isolation-query-violation:ignore:packages/issues (SELECT)

    pull_request_issues = pull_requests.map(&:issue).compact
    ordinary_issues = items.select(&:issue?).map(&:content).compact

    GitHub::PrefillAssociations.prefill_associations(
      pull_requests + pull_request_issues + ordinary_issues,
      :repository,
      available_records: items.map(&:repository).compact
    )
  end
end
