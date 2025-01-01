# frozen_string_literal: true

module HasSorting
  def change_sort_param(current_sort, current_sort_by = nil, sort_field = nil)
    return "asc" if current_sort_by != sort_field

    current_sort == "desc" ? "asc" : "desc"
  end

  def sort_icon(sort, current_sort_by = nil, sort_field = nil)
    return "arrow-up" if current_sort_by != sort_field

    case sort
    when "asc"
      "arrow-up"
    when "desc"
      "arrow-down"
    end
  end

  def sort_schema(current_sort_by, sort_field)
    current_sort_by == sort_field ? :default : :muted
  end
end
