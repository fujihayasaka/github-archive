# typed: strict
# frozen_string_literal: true

# This module provides an interface for working with "special" field types: those that link existing data
# from elsewhere on GitHub, typically via the `content` association on a `MemexProjectItem`.
module MemexProjectColumn::Interface::SpecialTypeSerializable
  extend ActiveSupport::Concern
  extend T::Helpers

  include MemexProjectColumn::Helper::Serializable
  include MemexProjectColumn::Interface::Serializable::WebApi

  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  class_methods do
    sig { returns(T::Boolean) }
    def special_type?
      true
    end

    sig { returns(T::Boolean) }
    def web_api_serializable? = true
  end

  sig do
    overridable.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(T.any(MemexProjectColumn::IDataSource::JSONValue, T::Array[MemexProjectColumn::IDataSource::JSONValue])))
  end
  def json_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = value(item, prefilled_associations:, redacted_issue_ids:)

    case value
    when Array
      value.compact.map(&:to_hash)
    else
      value&.to_hash
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
    value = value(item, prefilled_associations:, redacted_issue_ids:)
    value = Array.wrap(value).compact.map(&:to_csv)
    value.length > 1 ? value.join(", ") : value.first
  end

  sig do
    overridable
    .params(
      item: MemexProjectItem,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer]
    ).returns(T.nilable(String))
  end
  def string_value(item, prefilled_associations: nil, redacted_issue_ids: [])
    value = value(item, prefilled_associations:, redacted_issue_ids:)
    values = Array.wrap(value).compact.map(&:to_s)
    return if values.blank?

    values.join(", ")
  end

  # This helper can be used in `Indexable#preload_elasticsearch_document_data` implementations to make sure that the
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
    GitHub::PrefillAssociations.prefill_associations(items, [:issue]) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
    issues = items.map(&:issue).compact

    GitHub::PrefillAssociations.prefill_associations(items, [:content, :repository], available_records: issues)

    pull_requests = T.cast(items.select(&:pull_request?).map(&:content).compact, T::Array[PullRequest])
    GitHub::PrefillAssociations.prefill_associations(pull_requests, :issue, available_records: issues)

    repositories = items.map(&:repository).uniq
    GitHub::PrefillAssociations.prefill_associations(
      pull_requests + issues,
      :repository,
      available_records: repositories
    )
  end

  # Base implementation for all fields implementing this interface (special types), excluding those types
  # that are marked as special, but are not backed by an active record model directly, i.e. reviewers, title
  sig do
    override.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      ).
      returns(T.nilable(ValueReturn))
  end
  def value(item, prefilled_associations: nil, redacted_issue_ids: [])
    return unless value = serializable(item, prefilled_associations:, redacted_issue_ids:)

    serializable_value = T.cast(value, DataSourceSerializableValue)

    case serializable_value
    when Array
      serializable_value
        .compact
        .map(&:memex_project_column_value)
    else
      serializable_value.memex_project_column_value
    end
  end
end
