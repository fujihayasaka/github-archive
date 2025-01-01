# typed: strict
# frozen_string_literal: true

# This module provides helper methods for working with "generic" field types: those where the data they contain is
# defined by the end-user.
module MemexProjectColumn::Helper::GenericField
  extend ActiveSupport::Concern
  extend T::Helpers
  requires_ancestor { MemexProjectColumn::Field::Base }

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
end
