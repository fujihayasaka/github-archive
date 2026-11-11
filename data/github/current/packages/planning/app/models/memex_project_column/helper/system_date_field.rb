# typed: strict
# frozen_string_literal: true

# Shared behavior for system date fields (Created, Updated, Closed).
#
# These fields derive their values from denormalized item-level columns
# (e.g., issue_created_at, updated_at, issue_closed_at, created_at)
# rather than from content associations. They share the same serialization,
# querying, sorting, and existence-checking logic - only the specific
# timestamp differs, which each subclass provides via `content_timestamp`.
module MemexProjectColumn::Helper::SystemDateField
  extend ActiveSupport::Concern
  extend T::Helpers

  include ElasticsearchDateQueryHelper

  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }
  requires_ancestor { MemexProjectColumn::Interface::SpecialTypeSerializable }

  module ClassMethods
    # REST API serialization is intentionally disabled — these timestamps are
    # already returned on the item's content object, and including them as
    # separate field values adds unnecessary serialization overhead.
    sig { returns(T::Boolean) }
    def rest_api_serializable? = false
  end

  mixes_in_class_methods(ClassMethods)

  # ------------------------------------------------------------------
  # Abstract: each subclass must implement this to return the relevant
  # timestamp from the item's denormalized columns.
  # ------------------------------------------------------------------

  sig { abstract.params(item: MemexProjectItem).returns(T.nilable(ActiveSupport::TimeWithZone)) }
  def content_timestamp(item); end

  sig do
    params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    items.each_with_object({}) do |item, result|
      result[item.id] = content_timestamp(item)
    end
  end

  # ------------------------------------------------------------------
  # Elasticsearch indexing
  # ------------------------------------------------------------------

  sig { params(item: MemexProjectItem).returns(T.nilable(String)) }
  def elasticsearch_document(item)
    content_timestamp(item)&.utc&.iso8601
  end

  # ------------------------------------------------------------------
  # Web API serialization
  # ------------------------------------------------------------------

  sig do
    params(
      item: MemexProjectItem,
      prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
      redacted_issue_ids: T::Array[Integer],
    ).returns(T.nilable(MemexProjectColumn::IDataSource))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    timestamp = if preloaded_web_api_response_data?
      preloaded_web_api_response_data[item.id]
    else
      content_timestamp(item)
    end

    return unless timestamp

    MemexProjectColumnValue::DateTimeValue.new(
      value: timestamp.utc.iso8601,
    )
  end

  # ------------------------------------------------------------------
  # Elasticsearch querying / sorting / filtering
  # ------------------------------------------------------------------

  sig { params(value: String, context: Search::Memex::Context).returns(T.nilable(T::Hash[T.untyped, T.untyped])) }
  def query_strategy(value:, context:)
    date_query(field_path: query_by_value_path, date_value: value, context:)
  end

  sig { returns(String) }
  def group_by_value_path
    "field_values.#{field_value_name}"
  end

  sig { returns(String) }
  def chart_by_value_path = group_by_value_path

  sig { returns(String) }
  def slice_by_value_path = group_by_value_path

  sig { returns(String) }
  def query_by_value_path = group_by_value_path

  sig { params(direction: String).returns(T::Hash[T.untyped, T.untyped]) }
  def sort_fragment(direction:)
    build_version_compatible_sort_fragment(
      direction: direction,
      sort_by: "field_values.#{field_value_name}",
    )
  end

  sig { returns(T::Hash[T.untyped, T.untyped]) }
  def existence_fragment
    {
      nested: {
        path: "field_values",
        query: {
          bool: {
            filter: [
              elasticsearch_field_value_term_filter,
              {
                exists: {
                  field: "field_values.#{field_value_name}",
                },
              },
            ],
          },
        },
      },
    }
  end

  private

  sig { returns(Symbol) }
  def field_value_name
    T.cast(self, MemexProjectColumn::Field::Base).class.value_name
  end
end
