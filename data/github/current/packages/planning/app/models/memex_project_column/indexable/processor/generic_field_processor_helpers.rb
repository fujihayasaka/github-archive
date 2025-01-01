# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    module GenericFieldProcessorHelpers
      extend ActiveSupport::Concern
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer
      requires_ancestor { MemexProjectColumn::Indexable::Processor::Base }

      sig { returns(T.nilable(Integer)) }
      private def item_id
        message.dig(:project_item, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def field_id
        message.dig(:project_column, :id)
      end

      sig { returns(T.nilable(Integer)) }
      private def project_id
        message.dig(:project, :id)
      end

      sig { returns(T.nilable(String)) }
      private def column_data_type
        message.dig(:project_column, :data_type)
      end

      sig { returns(T.nilable(MemexProjectColumnValue)) }
      memoize private def memex_project_column_value
        MemexProjectColumnValue.includes(:memex_project_column, :memex_project_item)
          .find_by(memex_project_column_id: field_id, memex_project_item_id: item_id)
      end

      # Note that we fall back to the simple fetching helpers (project_item and field) to support the case
      # where the column value has been deleted and thus returns `nil`. Unless the field and/or item has been deleted,
      # we still want to continue with the update, removing the field from the field_values array entirely.
      sig { returns(T.nilable(MemexProjectItem)) }
      private def project_item
        memex_project_column_value&.memex_project_item || MemexProjectItem.find_by(id: item_id)
      end

      sig { returns(T.nilable(MemexProjectColumn::Field)) }
      private def field
        column = T.must(memex_project_column_value&.memex_project_column || MemexProjectColumn.find_by(id: field_id))
        column.to_field
      end
    end
  end
end
