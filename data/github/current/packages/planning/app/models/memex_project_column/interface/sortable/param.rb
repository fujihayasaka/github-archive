# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Sortable
  class Param < T::Struct
    prop :direction, String
    prop :column_id, T.any(Integer, String)

    sig { params(project: MemexProject).returns(T.nilable(Search::Queries::CursorPagination::SortField)) }
    def to_sort_fragment(project)
      return { archived_at: "desc" } if column_id == "archived_at"
      column = project.find_column_by_name_or_id(column_id)

      if column
        column.to_field&.sort_fragment(direction: direction)
      else
        nil
      end
    end
  end
end
