# typed: true
# frozen_string_literal: true

class Memex::ProjectListComponent < ApplicationComponent
  OPEN_FILTER_REGEX = /is\:open/i.freeze
  CLOSED_FILTER_REGEX = /is\:closed/i.freeze

  renders_one :header, -> (&block) do
    return nil if block.nil?

    Primer::Box.new(
      mb: 3,
      test_selector: "project-list-header"
    ) { block.call }
  end

  renders_one :controls, -> (&block) do
    Primer::Box.new(
      display: :flex,
      direction: :row,
      align_items: :center,
      mb: 3,
      style: "gap: 16px",
      test_selector: "project-list-controls"
    ) { block.call }
  end

  renders_one :blankslate, -> (&block) do
    return nil if block.nil?

    Primer::Beta::Blankslate.new { |c| block.call(c) }
  end

  def initialize(
    context:,
    projects:,
    owner:,
    is_recent_selected:,
    has_next_page:,
    cursor:,
    sort_query_cursor:,
    parsed_query:,
    open_memex_count:,
    closed_memex_count:,
    load_more_path:,
    write_accessible_project_ids:,
    team: nil
  )
    @context = context
    @projects = projects
    @owner = owner
    @is_recent_selected = is_recent_selected
    @has_next_page = has_next_page
    @cursor = cursor
    @sort_query_cursor = sort_query_cursor
    @parsed_query = parsed_query
    @open_memex_count = open_memex_count
    @closed_memex_count = closed_memex_count
    @write_accessible_project_ids = write_accessible_project_ids
    @team = team
    @load_more_path = load_more_path

    GitHub::PrefillAssociations.prefill_batch_method(@projects, :is_template?)
    GitHub::PrefillAssociations.prefill_associations(@projects, :latest_status_update)
  end

  memoize def has_search_filter?
    @parsed_query.full_text_query_terms.present?
  end

  memoize def has_template_filter?
    @parsed_query.has_template_filter?
  end

  memoize def org_projects_disabled?
    @owner && @owner.is_a?(Organization) && !@owner.organization_projects_enabled?
  end

  memoize def has_no_projects?
    scope = @owner.memex_projects.active_projects
    if @owner.is_a?(Organization) && @parsed_query.has_template_filter?
      scope = scope.templates
    end
    scope.empty?
  end

  memoize def org_empty?
    @context == Organization && has_no_projects?
  end

  memoize def user_empty?
    [User, MemexProject::ProjectsDashboardContext].include?(@context) && has_no_projects?
  end

  memoize def query
    @parsed_query.stringify
  end

  memoize def open_projects_path
    # Preserve the placement of the existing open/closed state filter in the query
    query = if @parsed_query.raw_query.match?(CLOSED_FILTER_REGEX)
      @parsed_query.raw_query.gsub(CLOSED_FILTER_REGEX, "is:open")
    else
      "#{@parsed_query.raw_query} is:open"
    end

    projects_path_with_query(Search::Queries::MemexProjectQuery.new(query).stringify)
  end

  memoize def closed_projects_path
    # Preserve the placement of the existing open/closed state filter in the query
    query = if @parsed_query.raw_query.match?(OPEN_FILTER_REGEX)
      @parsed_query.raw_query.gsub(OPEN_FILTER_REGEX, "is:closed")
    else
      "#{@parsed_query.raw_query} is:closed"
    end

    projects_path_with_query(Search::Queries::MemexProjectQuery.new(query).stringify)
  end

  memoize def projects_path
    projects_path_with_query(query)
  end

  private

  # TODO: Can we have a higher-level option here based on a higher-level context?
  def projects_path_with_query(query)
    if @context == Repository
      repo_projects_beta_path(
        @owner.display_login,
        query: query,
        is_search: true
      )
    elsif @context == Organization
      org_projects_path(
        org: @owner,
        query: query,
        is_search: true
      )
    elsif @context == User
      user_projects_path(
        @owner.display_login,
        query: query,
        is_search: true
      )
    elsif @context == Team
      team_projects_beta_path(
        @owner.display_login,
        query: query,
        is_search: true
      )
    else
      projects_dashboard_path(
        query: query,
        is_search: true
      )
    end
  end
end
