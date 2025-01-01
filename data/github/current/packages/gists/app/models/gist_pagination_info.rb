# typed: true
# frozen_string_literal: true

# This class handles white listing sort params and pagination info for
# GistsController and GistUsersController
class GistPaginationInfo
  attr_reader :params, :current_page

  def initialize(params, current_page, disable_sort: false)
    @params = params
    @current_page = current_page
    @disable_sort = disable_sort
  end

  # Public: Apply these options to a relation
  def apply_to_rel(rel, for_public: false)
    # total_entries
    rel = rel.order(Gist.sanitize_sql_for_order(sort_sql)) if sorting_enabled?
    rel = rel.limit(10).page(current_page)
    rel.total_entries = Gist::MAX_PUBLIC_GISTS_TO_PAGINATE if for_public
    rel
  end

  def sorting_enabled?
    !@disable_sort
  end

  # Internal: Only allow permitted sort field
  # Defaults to 'id' if an invalid sort param is given
  def sort_by
    case params[:sort]
    when "updated"
      "updated_at"
    else
      "id"
    end
  end

  # Internal: Only allow permitted sort direction
  # Defaults to 'desc' if an invalid direction is given
  def sort_direction
    %w{desc asc}.include?(params[:direction]) ? params[:direction] : "desc"
  end

  # Internal: The sort string as sql
  # This is done as a string so we can qualify the table fully
  def sort_sql
    "gists.#{sort_by} #{sort_direction}"
  end
end
