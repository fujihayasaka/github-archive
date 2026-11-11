# typed: true
# frozen_string_literal: true

class Memex::ProjectList::ItemsContainerComponent < ApplicationComponent
  def initialize(
    context:,
    projects:,
    owner:,
    is_recent_selected:,
    has_next_page:,
    query:,
    cursor:,
    sort_query_cursor:,
    load_more_path:,
    write_accessible_project_ids:,
    team: nil
  )
    @context = context
    @projects = projects
    @owner = owner
    @is_recent_selected = is_recent_selected
    @has_next_page = has_next_page
    @query = query
    @cursor = cursor
    @sort_query_cursor = sort_query_cursor
    @write_accessible_project_ids = write_accessible_project_ids
    @load_more_path = load_more_path
    @team = team

    GitHub::PrefillAssociations.prefill_associations(@projects, :latest_status_update)
  end
end
