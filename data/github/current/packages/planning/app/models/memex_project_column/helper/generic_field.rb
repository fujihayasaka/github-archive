# typed: strict
# frozen_string_literal: true

# This module provides helper methods for working with "generic" field types: those where the data they contain is
# defined by the end-user.
module MemexProjectColumn::Helper::GenericField
  extend ActiveSupport::Concern
  extend T::Helpers

  include MemexProjectColumn::Helper::Serializable
  include MemexProjectColumn::Interface::Serializable::WebApi

  abstract!

  requires_ancestor { MemexProjectColumn::Field::Base }

  module ClassMethods
    sig { returns(T::Boolean) }
    def web_api_serializable? = true
  end

  mixes_in_class_methods(ClassMethods)

  sig do
    params(item: MemexProjectItem, new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def update_mysql_field_value(item:, new_value:, actor:, suppress_hydro_events:)
    retry_on_find_or_create_error do
      if new_value.present?
        change_mysql_value(item:, new_value:, actor:, suppress_hydro_events:)
      else
        delete_mysql_value(item:, suppress_hydro_events:)
      end
    end
  end

  sig do
    params(item: MemexProjectItem, suppress_hydro_events: T::Boolean)
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def delete_mysql_value(item:, suppress_hydro_events:)
    target_column_value = item.find_column_value(id)
    return MemexProjectColumn::Interface::Writeable::PartialResult.success unless target_column_value.present?

    target_column_value.disable_hydro_event_instrumentation = suppress_hydro_events

    if target_column_value.destroy&.destroyed?
      item.memex_project_column_values.reset # Clear the cached association so subsequent reads reflect the deletion
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.failure("Failed to remove field value for #{data_type}")
    end
  end

  sig do
    params(item: MemexProjectItem, new_value: T.untyped, actor: User, suppress_hydro_events: T::Boolean)
    .returns(MemexProjectColumn::Interface::Writeable::PartialResult)
  end
  private def change_mysql_value(item:, new_value:, actor:, suppress_hydro_events:)
    target_column_value = item.find_or_build_column_value(id, actor)
    return MemexProjectColumn::Interface::Writeable::PartialResult.success unless target_column_value.present?

    target_column_value.disable_hydro_event_instrumentation = suppress_hydro_events

    # Note that this prefill is here to prevent extraneous queries on column-based
    # validation in MemexProjectColumnValue when we already have the column.
    # See this post for details on implementation: https://github.com/orgs/github/teams/engineering/discussions/467
    GitHub::PrefillAssociations.prefill_associations(
      target_column_value,
      :memex_project_column,
      available_records: [self]
    )

    if target_column_value.update(value: new_value) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      MemexProjectColumn::Interface::Writeable::PartialResult.success
    else
      MemexProjectColumn::Interface::Writeable::PartialResult.failure(
        "must be a valid value for #{data_type} column",
        attribute: :column_value
      )
    end
  end

  sig(:final) do
    override
      .params(items: T::Array[MemexProjectItem], fields: T::Array[MemexProjectColumn::Field::Base])
      .returns(T.nilable(T::Hash[Integer, T.untyped]))
  end
  private def preload_web_api_response_data(items:, fields:)
    return if preloaded_web_api_response_data?

    # Fetch data across all generic fields (not just the one against which this method was invoked) at once!
    generic_fields = fields.select { |f| f.generic_type? && !f.issue_field? }
    values_by_item_id = MemexProjectColumnValue
      .where(memex_project_item_id: items.map(&:id), memex_project_column_id: generic_fields.map(&:id))
      .group_by(&:memex_project_item_id)

    # Proactively cache the preloaded data in the `preloaded_web_api_response_data` instance variable of each
    # individual field.
    #
    # This is different from other implementations of `preload_web_api_response_data` which return a hash and allow
    # the `Serializable::WebApi` interface to handle the caching. Doing it this way allows us to cache data for all
    # generic fields at once so that we only ever pay this cost once.
    generic_fields.each do |field|
      field.preloaded_web_api_response_data = items.each_with_object({}) do |item, result|
        result[item.id] = values_by_item_id.fetch(item.id, []).find { |v| v.memex_project_column_id == field.id }
      end
    end

    # Return `nil` so that the `Serializable::WebApi` interface doesn't attempt to handle caching for us.
    nil
  end

  sig do
    override.
    overridable.
      params(
        item: MemexProjectItem,
        prefilled_associations: T.nilable(MemexProjectItem::PrefilledAssociations),
        redacted_issue_ids: T::Array[Integer],
      )
      .returns(T.nilable(SerializableReturn))
  end
  def serializable(item, prefilled_associations: nil, redacted_issue_ids: [])
    value_object = if preloaded_web_api_response_data?
      preloaded_web_api_response_data[item.id]
    else
      item.find_column_value(id)
    end

    value_object&.json_value
  end
end
