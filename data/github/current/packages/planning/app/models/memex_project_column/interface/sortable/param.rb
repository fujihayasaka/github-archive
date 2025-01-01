# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Sortable
  class Param < T::Struct
    prop :direction, String
    prop :column_id, T.any(Integer, String)

    sig { params(project: MemexProject).returns(T.nilable(Search::Queries::CursorPagination::SortField)) }
    def to_sort_fragment(project)
      return { archived_at: "desc" } if column_id == "archived_at"
      field = project.find_column_by_name_or_id(column_id)&.to_field

      if field.nil? || field.class.disabled?
        nil
      else
        field.sort_fragment(direction: direction)
      end
    end
  end
end
