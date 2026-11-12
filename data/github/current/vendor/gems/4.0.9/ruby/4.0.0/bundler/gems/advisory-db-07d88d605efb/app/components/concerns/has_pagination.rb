# frozen_string_literal: true

module HasPagination
  def normalize_page(page)
    [page.to_i, 1].max
  end

  def pagination(collection)
    will_paginate collection,
      params: request.query_parameters,
      inner_window: 2,
      outer_window: 0,
      previous_label: "Previous",
      next_label: "Next",
      class: "pagination text-center mt-3"
  end
end
