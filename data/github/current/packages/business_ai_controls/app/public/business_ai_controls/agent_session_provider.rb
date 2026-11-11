# typed: strict
# frozen_string_literal: true

module BusinessAiControls
  # Provides agent session data for AI Controls agent sessions view.
  # Supports server-side filtering by agent type and paginated queries.
  class AgentSessionProvider
    include AgentSessionMetadata

    # Default limit when no per_page is specified (server-side pagination)
    DEFAULT_PER_PAGE = 20

    # Maximum results per page to prevent excessive queries (server-side pagination)
    MAX_PER_PAGE = 100

    # Maximum number of suggestions to return for autocomplete
    MAX_SUGGESTIONS_LIMIT = 10

    # Time window for session queries (24 hours) - legacy default
    SESSION_TIME_WINDOW_HOURS = 24

    # Agent filters text for the frontend sessions filter component
    AGENT_COPILOT = "copilot-coding-agent"
    AGENT_REVIEW = "copilot-code-review"
    AGENT_CLAUDE = "claude"
    AGENT_CODEX = "codex"

    AGENT_TYPE_TO_ALIAS = T.let({
      AGENT_COPILOT => T.unsafe(Apps::Privileged::CopilotSWEAgent::PRODUCTION)[:alias],
      AGENT_REVIEW => T.unsafe(Apps::Privileged::CopilotPullRequestReviewer::PRODUCTION)[:alias],
      AGENT_CLAUDE => T.unsafe(Apps::Privileged::ClaudeAgent::PRODUCTION)[:alias],
      AGENT_CODEX => T.unsafe(Apps::Privileged::CodexAgent::PRODUCTION)[:alias],
    }.freeze, T::Hash[String, Symbol])

    # Map raw status values to UI icons
    STATUS_ICONS = T.let({
      "queued" => "clock",
      "in_progress" => "sync",
      "completed" => "check-circle",
      "failed" => "x-circle",
      "idle" => "pause",
      "waiting_for_user" => "person",
      "timed_out" => "clock",
      "cancelled" => "stop"
    }.freeze, T::Hash[String, String])

    # Fetches recent sessions with server-side filtering and pagination.
    #
    # @param business [Business] The business to fetch sessions for
    # @param user [User, nil] The current user (for feature flag checks)
    # @param page [Integer] The page number (1-indexed)
    # @param per_page [Integer] Number of results per page (default: 20, max: 100)
    # @param agent_type [String, nil] Filter by agent type: "coding", "code_review", or nil/all (server-side pagination only)
    # @param organization_id [Integer, nil] Filter by organization ID, or nil for all organizations (server-side pagination only)
    # @param timeframe_filter [String, nil] Filter by time window: "24h", "7d", or nil for default (24h)
    # @return [Hash] Sessions array and pagination metadata
    sig do
      params(
        business: Business,
        user: T.nilable(User),
        page: Integer,
        per_page: Integer,
        agent_types: T.nilable(T::Array[String]),
        organization_ids: T.nilable(T::Array[Integer]),
        statuses: T.nilable(T::Array[String]),
        timeframe_filter: T.nilable(String),
        repository_ids: T.nilable(T::Array[Integer]),
        user_ids: T.nilable(T::Array[Integer]),
      ).returns(T::Hash[String, T.untyped])
    end
    def self.fetch_recent_sessions(business:, user:, page:, per_page: DEFAULT_PER_PAGE, agent_types: nil, organization_ids: nil, statuses: nil, timeframe_filter: nil, repository_ids: nil, user_ids: nil)
      # Clamp per_page to valid range
      per_page = [[per_page, 1].max, MAX_PER_PAGE].min

      fetch_sessions_paginated(
        business: business,
        user: user,
        page: page,
        per_page: per_page,
        agent_types: agent_types,
        organization_ids: organization_ids,
        statuses: statuses,
        timeframe_filter: timeframe_filter,
        repository_ids: repository_ids,
        user_ids: user_ids,
      )
    end

    # Fetches sessions from the database with server-side filtering and pagination.
    sig do
      params(
        business: Business,
        user: T.nilable(User),
        page: Integer,
        per_page: Integer,
        agent_types: T.nilable(T::Array[String]),
        organization_ids: T.nilable(T::Array[Integer]),
        statuses: T.nilable(T::Array[String]),
        timeframe_filter: T.nilable(String),
        repository_ids: T.nilable(T::Array[Integer]),
        user_ids: T.nilable(T::Array[Integer])
      ).returns(T::Hash[String, T.untyped])
    end
    def self.fetch_sessions_paginated(business:, user:, page:, per_page:, agent_types:, organization_ids:, statuses:, timeframe_filter:, repository_ids:, user_ids:)
      # Calculate time cutoff based on timeframe filter (default to 24 hours)
      twenty_four_hours = SESSION_TIMEFRAME_FILTERS[:twenty_four_hours]
      seven_days = SESSION_TIMEFRAME_FILTERS[:seven_days]

      time_cutoff = case timeframe_filter
      when seven_days[:value]
        T.cast(seven_days[:number], Integer).days.ago.beginning_of_day
      else
        T.cast(twenty_four_hours[:number], Integer).hours.ago
      end

      # Build base query with timeframe filter
      base_query = business.copilot_agent_sessions
        .where(created_at: time_cutoff..)
        .includes(:agent, :resource, :organization, repository: :owner)
        .order(created_at: :desc)

      # Apply organization filter if specified
      base_query = base_query.where(organization_id: organization_ids) if organization_ids.present?

      # Apply repository filter if specified
      base_query = base_query.where(repository_id: repository_ids) if repository_ids.present?

      # Apply agent type filter if specified
      base_query = apply_agent_type_filter(base_query, agent_types: agent_types)

      # Apply status type filter if specified
      base_query = base_query.where(state: statuses) if statuses.present?

      # Apply user filter if specified
      base_query = base_query.where(user_id: user_ids) if user_ids.present?

      # Get total count for pagination
      total_count = base_query.count

      # No need to send this log for every page - log it only for the first page to avoid noise, but still get visibility into total session count
      if page == 1
        GitHub.logger.info("agent session total count",
          "gh.business.id": business.id,
          "gh.business.slug": business.slug,
          "gh.agent_sessions.count": total_count,
        )
      end

      # Calculate pagination
      total_pages = [(total_count.to_f / per_page).ceil, 1].max
      offset = (page - 1) * per_page

      # Fetch paginated results
      sessions = base_query.offset(offset).limit(per_page)

      # Transform sessions to response format
      sessions_data = sessions.map do |session|
        transform_session_to_response(session, user)
      end

      {
        "sessions" => sessions_data,
        "pagination" => {
          "current_page" => page,
          "total_pages" => total_pages,
          "total_count" => total_count,
          "per_page" => per_page,
          "has_previous" => page > 1,
          "has_next" => page < total_pages
        }
      }
    end

    # Applies agent type filter to the query by looking up agent IDs for the specified category.
    # Filters sessions by agent_id using the privileged app registry.
    sig { params(query: T.untyped, agent_types: T.nilable(T::Array[String])).returns(T.untyped) }
    def self.apply_agent_type_filter(query, agent_types: nil)
      return query if agent_types.blank?

      agent_ids = agent_types.filter_map do |t|
        agent_alias = AGENT_TYPE_TO_ALIAS[t]
        Apps::Privileged.integration(agent_alias)&.id
      end

      return query if agent_ids.blank?

      query.where(agent_id: agent_ids, agent_type: "Integration")
    end

    # Paginates a list of sessions.
    sig { params(sessions: T::Array[T::Hash[String, T.untyped]], page: Integer, per_page: Integer).returns(T::Hash[String, T.untyped]) }
    def self.paginate_sessions(sessions, page, per_page)
      total_count = sessions.length
      total_pages = [(total_count.to_f / per_page).ceil, 1].max
      offset = (page - 1) * per_page
      sessions_for_page = sessions[offset, per_page] || []

      {
        "sessions" => sessions_for_page,
        "pagination" => {
          "current_page" => page,
          "total_pages" => total_pages,
          "total_count" => total_count,
          "per_page" => per_page,
          "has_previous" => page > 1,
          "has_next" => page < total_pages
        }
      }
    end

    # Transforms a single session record to the API response format.
    sig { params(session: Copilot::AgentSession, user: T.nilable(User)).returns(T::Hash[String, T.untyped]) }
    def self.transform_session_to_response(session, user)
      repo = T.must(session.repository)
      owner = T.must(repo.owner)
      created_at = session.created_at
      agent = session.agent

      # Generate the URL to the session
      url = generate_session_url(session, repo, owner)

      # Check if the current user has access to the repository.
      # Note: repo.is_a?(Repository) is required for Sorbet type narrowing. session.repository returns
      # Repositories::IRepository (interface), but readable_by? is only defined on Repository (concrete class).
      # The is_a? check type-narrows for Sorbet without needing T.cast.
      accessible = if user && repo.is_a?(Repository)
        repo.readable_by?(user)
      end

      agent_display_name = Apps::Privileged.property(:agent_session_activity_display_name, app: agent) || agent.name

      response = {
        "id" => session.copilot_session_id,
        "status" => session.state,
        "status_display" => STATUS_DISPLAY_NAMES[session.state],
        "status_icon" => STATUS_ICONS[session.state],
        "title" => session.name,
        "agent" => {
          "name" => agent_display_name,
        },
        "repository" => {
          "owner" => owner.display_login,
          "name" => repo.name,
          "full_name" => repo.name_with_display_owner,
        },
        "started_at" => created_at.iso8601,
        "time_since_start" => time_since(created_at),
        "url" => url,
        "event_type" => session.event_type,
      }
      # Add accessible field only when it's been calculated (not nil)
      response["accessible"] = accessible unless accessible.nil?
      response
    end

    # Generates the URL for a session based on resource type.
    sig { params(session: Copilot::AgentSession, repo: Repositories::IRepository, owner: T.untyped).returns(T.nilable(String)) }
    def self.generate_session_url(session, repo, owner)
      helpers = Rails.application.routes.url_helpers
      return nil unless helpers.respond_to?(:copilot_agent_task_path)

      case session.resource_type
      when "PullRequest"
        if session.resource&.is_a?(PullRequest)
          pull_request = T.cast(session.resource, PullRequest)
          helpers.copilot_agent_task_path(
            global_id: pull_request.global_relay_id,
            session_id: session.copilot_session_id
          )
        end
      end
    end

    sig { params(started_at: Time).returns(String) }
    def self.time_since(started_at)
      time_diff = Time.current - started_at
      hours = (time_diff / 1.hour).floor
      minutes = ((time_diff % 1.hour) / 1.minute).floor

      if hours > 0
        "#{hours} hour#{'s' if hours != 1} ago"
      else
        "#{minutes} minute#{'s' if minutes != 1} ago"
      end
    end

    # Fetches organizations that have agent sessions for a business.
    # Returns a list of organizations with their id, name, and avatar_url.
    # Uses two separate queries to respect domain boundaries (copilot_agent_sessions and
    # users/organizations are in different domains and cannot be joined).
    sig { params(business: Business).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_organizations_with_sessions(business)
      time_cutoff = SESSION_TIME_WINDOW_HOURS.hours.ago

      # Get distinct organization IDs from sessions in the time window
      # We use two separate queries to respect domain boundaries (copilot_agent_sessions and users/organizations
      # are in different domains and cannot be joined)
      org_ids = business.copilot_agent_sessions
        .where(created_at: time_cutoff..)
        .distinct
        .pluck(:organization_id)
        .compact

      return [] if org_ids.empty?

      # Fetch organizations - filter to only those that still exist
      # If an org was deleted between the pluck and this query, it simply won't be included
      Organization.where(id: org_ids).order(:login).map do |org|
        {
          "id" => org.id,
          "name" => org.display_login,
          "avatar_url" => org.primary_avatar_url
        }
      end
    rescue StandardError => e
      # Log error but return empty array to avoid breaking the page
      Rails.logger.error "[AGENT_SESSION_PROVIDER] Failed to fetch organizations: #{e.message}"
      []
    end

    # Fetches organization suggestions from the database
    sig { params(business: Business, query: String, limit: Integer).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_organization_suggestions(business:, query:, limit:)
      # Limit may not exceed MAX_SUGGESTIONS_LIMIT
      limit = MAX_SUGGESTIONS_LIMIT if limit > MAX_SUGGESTIONS_LIMIT

      # Match organizations where login starts with the query (prefix match)
      # Sanitize query to escape LIKE wildcards (%, _) so they're treated literally
      sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
      organizations = business.organizations
        .where("login LIKE ?", "#{sanitized_query}%")
        .order(:login)
        .limit(limit)

      organizations.map do |org|
        {
          "id" => org.id,
          "name" => org.display_login,
          "avatar_url" => org.primary_avatar_url
        }
      end
    end

    # Fetches repository suggestions for autocomplete based on a search query.
    # Returns repositories matching the query prefix, limited to the specified count.
    sig { params(business: Business, query: String, limit: Integer).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_repository_suggestions(business:, query:, limit:)
      # Limit may not exceed MAX_SUGGESTIONS_LIMIT
      limit = MAX_SUGGESTIONS_LIMIT if limit > MAX_SUGGESTIONS_LIMIT
      # Match repositories where name starts with the query (prefix match)
      # Sanitize query to escape LIKE wildcards (%, _) so they're treated literally
      sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)

      # Get organization IDs for this business (separate query due to cross-shard limitation)
      org_ids = business.organization_ids
      return [] if org_ids.empty?

      # Fetch repositories belonging to the business's organizations
      repositories = Repository.where(owner_id: org_ids)
        .where("name LIKE ?", "#{sanitized_query}%")
        .includes(:owner)
        .order(:name)
        .limit(limit)

      repositories.map do |repo|
        {
          "name" => repo.name,
          "value" => repo.name_with_display_owner,
          "description" => repo.owner_display_login,
        }
      end
    end

    # Fetches user suggestions from users that have agent sessions for the business
    sig { params(business: Business, query: String, limit: Integer).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_user_suggestions(business:, query:, limit:)
      sanitized_query = ActiveRecord::Base.sanitize_sql_like(query)
      users = business.members
        .where("login LIKE ?", "#{sanitized_query}%")
        .order(:login)
        .limit(limit)

      users.map do |user|
        {
          "id" => user.id,
          "login" => user.display_login,
          "name" => user.display_login,
          "full_name" => user.display_name || user.display_login,
          "avatar_url" => user.primary_avatar_url,
        }
      end
    end

    # Returns the list of available agent types for filtering agent sessions.
    sig { returns(T::Array[T::Hash[Symbol, T.untyped]]) }
    def self.session_agent_filters
      [
        {
          display_name: "Copilot Cloud Agent",
          value: AGENT_COPILOT,
          avatar_url: AgenticApp::CopilotAgent.instance.integration&.preferred_avatar_url,
        },
        {
          display_name: "Copilot Code Review",
          value: AGENT_REVIEW,
          avatar_url: AgenticApp::CopilotAgent.instance.integration&.preferred_avatar_url,
        },
        {
          display_name: "Claude",
          value: AGENT_CLAUDE,
          avatar_url: AgenticApp::ClaudeAgent.instance.integration&.preferred_avatar_url,
        },
        {
          display_name: "Codex",
          value: AGENT_CODEX,
          avatar_url: AgenticApp::CodexAgent.instance.integration&.preferred_avatar_url,
        },
      ]
    end
  end
end
