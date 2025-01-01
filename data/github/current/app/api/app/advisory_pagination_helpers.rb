# typed: true
# frozen_string_literal: true

module Api::App::AdvisoryPaginationHelpers
  extend T::Helpers

  DEFAULT_CURSOR_PAGINATION_RESULT_SIZE = 30

  def paginate_advisories(advisories, request_params)
    before = request_params[:before].presence
    after = request_params[:after].presence
    per_page = request_params[:per_page].presence || DEFAULT_CURSOR_PAGINATION_RESULT_SIZE

    first = per_page
    last = nil

    # if per_page is used with before, we need to reset first param to what is passed in
    if request_params.key?(:before) && request_params.key?(:per_page)
      last = per_page
      first = nil
    end

    first = first.to_i if first
    last = last.to_i if last

    Platform::ConnectionWrappers::Relation.new(
      advisories,
      before: before,
      after: after,
      first: first,
      last: last,
    )
  end

  def set_cursor_based_pagination_headers(advisories_platform_relation)
    page_info = advisories_platform_relation.page_info

    if advisories_platform_relation.has_next_page
      @links.add_current({ after: page_info.end_cursor, before: nil, page: nil }, rel: "next")
    end

    if advisories_platform_relation.has_previous_page
      @links.add_current({ before: page_info.start_cursor, after: nil, page: nil }, rel: "prev")
    end
  end
end
