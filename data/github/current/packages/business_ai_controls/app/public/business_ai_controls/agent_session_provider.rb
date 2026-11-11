# typed: strict
# frozen_string_literal: true

module BusinessAiControls
  # Provides agent session data for AI Controls agent sessions view.
  # Currently returns mock data for development, but will be updated to fetch
  # real agent session activity data when available.
  class AgentSessionProvider
    # The maximum number of sessions to query from the database.
    SESSIONS_QUERY_LIMIT = 1000

    # Map raw status values to user-friendly display names
    STATUS_DISPLAY_NAMES = T.let({
      "queued" => "Queued",
      "in_progress" => "In Progress",
      "completed" => "Completed",
      "failed" => "Failed",
      "idle" => "Idle",
      "waiting_for_user" => "Waiting for User",
      "timed_out" => "Timed Out",
      "cancelled" => "Cancelled"
    }, T::Hash[String, String])

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
    }, T::Hash[String, String])

    sig { params(business: Business, user: T.nilable(User), page: Integer, per_page: Integer).returns(T::Hash[String, T.untyped]) }
    def self.fetch_recent_sessions(business:, user:, page:, per_page: 20)
      all_sessions = fetch_all_sessions(business, user)

      # Calculate pagination
      total_sessions = all_sessions.length
      total_pages = (total_sessions.to_f / per_page).ceil
      offset = (page - 1) * per_page
      sessions_for_page = all_sessions[offset, per_page] || []

      {
        "sessions" => sessions_for_page,
        "pagination" => {
          "current_page" => page,
          "total_pages" => total_pages,
          "total_count" => total_sessions,
          "per_page" => per_page,
          "has_previous" => page > 1,
          "has_next" => page < total_pages
        }
      }
    end

    sig { params(business: ::Business, user: T.nilable(User)).returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.fetch_all_sessions(business, user)
      use_real_data = business.feature_flag_enabled?(:enterprise_ai_controls, default: false) && \
        business.feature_flag_enabled?(:agent_sessions_provide_real_data, default: false)
      return generate_mock_sessions unless use_real_data

      # Check feature flag once to determine URL format
      use_immersive_url = FeatureFlag.vexi.enabled?(:copilot_swe_agent_progress_commands, user, default: false)

      # Filter to sessions from the last 24 hours
      twenty_four_hours_ago = 24.hours.ago
      business.copilot_agent_sessions
        .where(created_at: twenty_four_hours_ago..)
        .includes(:agent, :resource, repository: :owner)
        .order(created_at: :desc)
        .limit(SESSIONS_QUERY_LIMIT)
        .map do |session|
        repo = T.must(session.repository)
        owner = T.must(repo.owner)
        created_at = session.created_at
        agent = session.agent

        # Generate the URL to the session
        url = case session.resource_type
        when "PullRequest"
          if session.resource&.is_a?(PullRequest)
            pull_request = T.cast(session.resource, PullRequest)
            # Use the immersive copilot task URL if feature flag is enabled, otherwise use repo-scoped URL
            if use_immersive_url
              Rails.application.routes.url_helpers.copilot_agent_task_path(
                global_id: pull_request.global_relay_id,
                session_id: session.copilot_session_id
              )
            else
              Rails.application.routes.url_helpers.repo_agent_session_path(
                user_id: owner.display_login,
                repository: repo.name,
                pull_number: pull_request.number,
                session_id: session.copilot_session_id
              )
            end
          else
            nil
          end
        else
          # Unknown or unsupported resource type
          nil
        end

        {
          "id" => session.copilot_session_id,
          "status" => session.state,
          "status_display" => STATUS_DISPLAY_NAMES[session.state],
          "status_icon" => STATUS_ICONS[session.state],
          "title" => session.name,
          "agent" => {
            "name" => Apps::Privileged.property(:agent_session_activity_display_name, app: agent) || agent.name,
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
      end
    end

    sig { returns(T::Array[T::Hash[String, T.untyped]]) }
    def self.generate_mock_sessions
      statuses = %w(queued in_progress completed failed idle waiting_for_user timed_out cancelled)

      repositories = [
        { "owner" => "github", "name" => "github" },
        { "owner" => "microsoft", "name" => "vscode" },
        { "owner" => "facebook", "name" => "react" },
        { "owner" => "vercel", "name" => "next.js" },
        { "owner" => "rails", "name" => "rails" },
        { "owner" => "nodejs", "name" => "node" },
        { "owner" => "typescript", "name" => "typescript" },
        { "owner" => "python", "name" => "cpython" }
      ]

      session_titles = [
        "Debug authentication flow",
        "Implement new feature",
        "Fix performance issue",
        "Update dependencies",
        "Add unit tests",
        "Refactor legacy code",
        "Review pull request",
        "Deploy to production",
        "Investigate bug report",
        "Optimize database queries"
      ]

      agent_names = [
        "GitHub Copilot",
        "Code Review Bot",
        "Test Assistant",
        "Security Scanner",
        "Performance Analyzer",
        "Documentation Helper",
        "Refactoring Agent"
      ]

      event_types = %w[
        push
        pull_request
        pull_request_review
        pull_request_comment
        issue_comment
        issues
      ]

      # Generate 47 mock sessions (enough for pagination testing)
      sessions = (1..47).map do |i|
        status = statuses.sample
        repo = repositories.sample
        title = session_titles.sample
        agent_name = agent_names.sample
        event_type = event_types.sample

        # Generate timestamps for last 24 hours
        hours_ago = rand(24)
        minutes_ago = rand(60)
        started_at = Time.current - hours_ago.hours - minutes_ago.minutes

        # Generate a mock URL to demonstrate the structure
        # In a real scenario, this would link to an actual pull request session
        mock_pull_number = rand(1..999)
        session_id = "session_#{i}"
        url = Rails.application.routes.url_helpers.repo_agent_session_path(
          user_id: repo["owner"],
          repository: repo["name"],
          pull_number: mock_pull_number,
          session_id: session_id
        )

        {
          "id" => "session_#{i}",
          "status" => status,
          "status_display" => STATUS_DISPLAY_NAMES[status],
          "status_icon" => STATUS_ICONS[status],
          "title" => title,
          "agent" => {
            "name" => agent_name,
          },
          "repository" => {
            "owner" => repo["owner"],
            "name" => repo["name"],
            "full_name" => "#{repo["owner"]}/#{repo["name"]}"
          },
          "started_at" => started_at.iso8601,
          "time_since_start" => time_since(started_at),
          "url" => url,
          "event_type" => event_type,
        }
      end
      sessions.sort_by { |session| Time.parse(session["started_at"]) }.reverse
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
  end
end
