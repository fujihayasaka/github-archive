
# typed: true
# frozen_string_literal: true

module MemexProject::SharedMemexProjectsDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  CAP_FILTER_BUFFER = 20

  requires_ancestor { Object }

  class MemexProjectsSearchResult
    attr_reader :memex_projects, :next_page_cursor, :total_open_count, :total_closed_count, :sort_query_cursor

    def initialize(memex_projects:, next_page_cursor:, total_open_count:, total_closed_count:, sort_query_cursor:)
      @memex_projects = memex_projects
      @next_page_cursor = next_page_cursor
      @total_open_count = total_open_count
      @total_closed_count = total_closed_count
      @sort_query_cursor = sort_query_cursor
    end

    def has_next_page?
      !!next_page_cursor
    end
  end

  # Returns a list of projects that a user has recently visited
  #
  # viewer - the user for whom to fetch the recently visited projects
  # limit - Optional Integer number of results to return, defaults to 20
  #
  # Returns ActiveRecord::Relation of MemexProjects with creator info
  sig { params(viewer: T.nilable(User), cap_filter: T.nilable(ConditionalAccess::Filter), limit: Integer).returns(T.nilable(ActiveRecord::Relation)) }
  def recently_visited_projects(viewer:, cap_filter:, limit: 20)
    # accessing this method in any other context is an error
    T.bind(self, T.any(Organization::MemexProjectsDependency, MemexProject::ProjectsDashboardContext, User::MemexProjectsDependency))

    return if viewer.nil?

    should_cap_filter = viewer.feature_enabled?(:cap_filter_projects_dashboard) && cap_filter.present?

    # Query for open projects visited by the user
    recently_visited_projects = memex_projects.open_projects.joins(:memex_project_visits)
      .where("memex_project_visits.viewer_id = ?", viewer.id)
      .order("memex_project_visits.last_visited_at DESC", number: :desc)
      # we need to limit here because we will be executing this query to perform cap_filter checking
      .limit(limit + (should_cap_filter ? CAP_FILTER_BUFFER : 0))

    # Sends user's visited projects to Authzd to ensure that user still has read access to them
    recently_visited_projects = accessible_memexes_scope(recently_visited_projects, viewer, "read", :batching)

    cap_filtered_projects = if should_cap_filter
      authorized_ids = cap_filter.authorized_resources(recently_visited_projects).pluck(:id)
      recently_visited_projects.where(id: authorized_ids)
    else
      recently_visited_projects
    end

    # Returns a list of recently viewed projects for display that the user has read access to
    cap_filtered_projects.includes(:latest_status_update)
      .limit(limit)
  end

  def remove_from_recently_visited_projects(viewer: nil, memex_project: nil)
    T.bind(self, T.any(User, Organization)) # accessing this method in any other context is an error
    return if viewer.nil? || memex_project.nil?
    recently_visited_project = memex_project.memex_project_visits
            .find_by(viewer_id: viewer.id, owner_id: id, owner_type: type)
    recently_visited_project&.destroy
  end

  def prepare_scope_for_search(base_scope:, query:, viewer: nil, cursor: nil, sort_query_cursor: nil, use_full_term_query: false)
    sort_key, sort_direction = query.sort_filter

    # Legacy number only based pagination
    if cursor && sort_query_cursor.nil?
      base_scope = base_scope.where("number <= ?", cursor.to_i)
    # Sort based pagination
    elsif sort_query_cursor.present? && sort_key.present?
      sort_comparator = sort_direction == "asc" ? ">" : "<"
      case sort_key
      when "title"
        # Title needs to be cast to a string from varbinary in order to compare it
        base_scope = base_scope.where(
          "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) #{sort_comparator} ?",
          MemexProject::DEFAULT_TITLE, sort_query_cursor
        ).or(
          base_scope.where(
            "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) = ? AND number <= ?",
            MemexProject::DEFAULT_TITLE,
            sort_query_cursor,
            cursor.to_i
          )
        )
      when "updated_at", "created_at"
        date_time_cursor = DateTime.parse(sort_query_cursor)
        base_scope = base_scope.where(
          "memex_projects.#{sort_key} #{sort_comparator} ?",
          date_time_cursor
          ).or(
            base_scope.where(
              "memex_projects.#{sort_key} = ? AND number <= ?",
              date_time_cursor,
              cursor.to_i
            )
          )
      end
    end

    if query.creator_filter.any?
      login, extra = query.creator_filter.to_a

      # If there are more than one creators present, we can zero out the results early as no project can contain
      # multiple creators.
      base_scope = if extra.present?
        base_scope.none
      else
        login = viewer&.display_login if login == Search::Query::MACRO_ME
        creator = User.find_by(login: login)
        base_scope.where(creator_id: creator&.id)
      end
    end

    # If use_full_term_query is true, use the full query string for the title search, rather than just
    # the first word (default). This is useful when providing a more narrow set of search results.
    if use_full_term_query && query.single_term_query
      base_scope = base_scope.where(
        # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
        # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
        "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ?",
        MemexProject::DEFAULT_TITLE,
        "%#{query.single_term_query}%"
      )
    # This intentionally uses just the first full-text query term. Empirically this seems to be good
    # enough, and it reduces the number of wildcards we need to insert into the query (which likely
    # helps performance a bit, even though it is the leading wildcard that breaks index usage).
    elsif (term = query.full_text_query_terms.first)
      base_scope = base_scope.where(
        # Since title is a VARBINARY column, we ordinarily cannot compare a value to it using LIKE.
        # To fix that, first cast it to a UTF-8 string (whose collation is case-insensitive).
        "CAST(COALESCE(title, ?) AS CHAR CHARACTER SET utf8mb4) LIKE ?",
        MemexProject::DEFAULT_TITLE,
        "%#{term}%"
      )
    end

    # When the user is viewing the templates index, we want to filter out all template projects by default. When the
    # user is filtering by templates we'll only include templates.
    if query.state_filters.include?("template")
      base_scope = base_scope.templates
    end

    # This return is required!
    base_scope
  end

  def sort_and_return_search_results(query:, scope:, limit: 30)
    # To assist with generating scopes necessary to count the total number of open/closed and public/private projects
    # we use this base scope to generate the necessary filtering scopes based on the user input.
    counts_scope = scope.active_projects
    if query.state_filters.include?("template")
      counts_scope = counts_scope.templates
    end

    # If is:public and is:private are both provided to the search query, we can zero out the results early as no
    # projects will have both be public and private.
    if query.state_filters.include?("public") && query.state_filters.include?("private")
      counts_scope = counts_scope.none
    elsif query.state_filters.include?("public")
      counts_scope = counts_scope.public_projects
    elsif query.state_filters.include?("private")
      counts_scope = counts_scope.private_projects
    end

    # Using the counts scope with filters applied needed for counts, we can continue to build the filter scope.
    memexes = counts_scope

    # If is:open and is:closed are both provided to the search query, we can zero out the results early as no projects
    # will have both the open and closed state.
    #
    # Additionally, if is:closed is not present in the query only return open projects by default.
    if query.state_filters.include?("open") && query.state_filters.include?("closed")
      # Clearing out the counts_scope is also necessary when both open and closed are provided.
      memexes = counts_scope = memexes.none
    elsif query.state_filters.include?("closed")
      memexes = memexes.closed_projects
    elsif query.state_filters.include?("open") || query.state_filters.empty?
      # If no open/closed filter is specified the default behavior is returning open projects.
      memexes = memexes.open_projects
    end

    memexes = memexes.includes(:creator, :latest_status_update)

    # Apply sorting
    sort_key, sort_direction = query.sort_filter
    memexes = if sort_key == "title"
      memexes.order(Arel.sql("TRIM(CAST(COALESCE(title, #{MemexProject.connection.quote(MemexProject::DEFAULT_TITLE)}) AS CHAR CHARACTER SET utf8mb4)) #{sort_direction}"), number: :desc)
    elsif sort_key == "updated_at" || sort_key == "created_at"
      memexes.order(sort_key => sort_direction, :number => :desc)
    else
      memexes.order(number: :desc)
    end

    memexes = (limit.present? ? memexes.limit(limit + 1) : memexes).all.to_a
    next_memex = limit.present? && memexes.length > limit ? memexes.pop : nil

    sort_query_cursor_for_column = if next_memex
      case sort_key
      when "title"
        next_memex[sort_key] || MemexProject::DEFAULT_TITLE
      when "updated_at", "created_at"
        next_memex[sort_key]
      end
    end

    MemexProject::SharedMemexProjectsDependency::MemexProjectsSearchResult.new(
      memex_projects: memexes,
      next_page_cursor: next_memex&.number,
      sort_query_cursor: sort_query_cursor_for_column,
      total_open_count: counts_scope.open_projects.count,
      total_closed_count: counts_scope.closed_projects.count,
    )
  end

  # Returns a page of memex projects matching the given search query.
  #
  # query - Search::Queries::MemexProjectQuery
  # cursor - Optional Integer memex number that the returned page should start on (inclusively).
  #   If omitted, the page will begin with the most recently created memex.
  # limit - Option Integer number of results to return. Defaults to 30.
  # sort_query_cursor - Optional string value of the field sorted on by the current sort query that the returned page
  #   should start on (inclusively). If omitted, the page will begin with the first ordered project for that sort
  # filter_ids - Optional array of memex ids to filter the results by.
  # use_full_term_query - Optional flag to query project titles against a full query term, rather than just the first word
  #
  # Returns MemexProjectsSearchResult.
  def search_memex_projects(query:, viewer: nil, cursor: nil, limit: 30, sort_query_cursor: nil, filter_ids: [], recently_visited_projects: [], min_permission_level: "read", use_full_term_query: false)
    # This module can be arbitrarily included, but this method must only be called in these contexts:
    T.bind(self, T.any(User, Organization, Team, Repository, MemexProject::ProjectsDashboardContext))

    search_scope = recently_visited_projects.any? ? recently_visited_projects : memex_projects
    base_scope = prepare_scope_for_search(base_scope: search_scope, query: query, viewer: viewer, cursor: cursor, sort_query_cursor: sort_query_cursor, use_full_term_query: use_full_term_query)

    start_time = GitHub::Dogstats.monotonic_time
    scope = accessible_memexes_scope(base_scope, viewer, min_permission_level, filter_ids: filter_ids)

    GitHub.dogstats.distribution(
      "memex.index.permissions.check",
      GitHub::Dogstats.duration(start_time))

    sort_and_return_search_results(
      query: query,
      scope: scope,
      limit: limit,
    )
  end

  def accessible_memexes_scope
    raise NotImplementedError
  end

  # Returns the accessible memexes using batching
  # If `return_ids` is true the query will be executed and an array of ids will be returned
  sig do
    params(
      search_scope: ActiveRecord::Relation,
      user: T.nilable(User),
      min_permission_level: T.any(String, Symbol),
      filter_ids: T::Array[Integer],
      return_ids: T::Boolean
    ).returns(
      Promise[T.any(T::Array[Integer], ActiveRecord::Relation)]
    )
  end
  def async_accessible_memexes_scope_using_batching(
    search_scope,
    user,
    min_permission_level,
    filter_ids: [],
    return_ids: false
  )
    # Using T.unsafe here because there is no easy way that I can see to type the `filter_spam_for` generically
    # on the ActiveRecord::Relation in the `params` block above.
    memex_ids = T.unsafe(search_scope).active_projects.filter_spam_for(user).pluck(:id)
    memex_ids = memex_ids & filter_ids if filter_ids.any?

    # Performing Batch authorize request to Authzd for private projects
    MemexProject.async_accessible_memexes(
      user,
      memex_ids,
      min_permission_level
    ).then do |accessible_memexes|
      ids = accessible_memexes.map(&:id)
      if return_ids
        ids
      else
        search_scope.where(id: ids)
      end
    end
  end

  def accessible_memexes_scope_using_enumeration(search_scope, user, min_permission_level, filter_ids: [], return_ids: false, scoped: true)
    # Enumeration API does not support anonymous users
    if user.nil?
      if return_ids
        raise "Anonymous users are not supported in this case."
      end
      if min_permission_level == "read"
        return search_scope.public_projects
      end

      return search_scope.none
    end

    accessible_memexes_ids = cached_accessible_memexes_ids_for_actor(user_id: user.id, relationship: min_permission_level, scoped: scoped)

    # Comparing a user's visited projects with all projects in current orgs that are accessible to the current user
    accessible_memexes_ids = accessible_memexes_ids & filter_ids if filter_ids.present?

    if return_ids
      accessible_memexes_ids
    else
      search_scope.where(id: accessible_memexes_ids)
    end
  end

  def cached_accessible_memexes_ids_for_actor(user_id:, relationship: :read, scoped: true)
    @accessible_memexes_ids ||= {}
    key = "#{user_id}--#{relationship}"

    if @accessible_memexes_ids.has_key?(key)
      @accessible_memexes_ids[key]
    else
      @accessible_memexes_ids[key] = accessible_memexes_ids_for_actor(user_id: user_id, relationship: relationship, scoped: scoped)
    end
  end

  def accessible_memexes_ids_for_actor(user_id:, relationship: :read, scoped: true)
    T.bind(self, T.any(User, Organization)) # accessing this method in any other context is an error
    if scoped
      options = Authzd::Enumerator::Options.new(scope: "organization", scope_target_id: id, relationship: relationship.to_s)
    else
      options = Authzd::Enumerator::Options.new(relationship: relationship.to_s)
    end
    authzd_req = Authzd::Enumerator::ForActorRequest.new(
      actor_id: user_id,
      actor_type: "User",
      subject_type: "MemexProject",
      options: options
    )
    response = Authzd.enumerator_client.for_actor(authzd_req)

    raise "Unable to fetch accessible memex projects. Error: #{response.error}" if response.error.present?

    Array(response.data&.result_ids)
  end

end
