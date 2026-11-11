# frozen_string_literal: true

# Activity::PauseManager is an observer on the events captured by any instance
# of Activity::Logger.
#
# It is responsible for determining which events make changes to a Repository's
# standing, such periods of inactivity or resumed use, and updating the
# Repository's pause state in response.
#
module Activity
  class PauseManager
    attr_reader :repo

    ACTIVITY_MONITOR_CONTEXT = "repository_activity_monitor"

    # These are events where Dependabot has performed work on a Repository
    # which act as a signal that we should monitor the repository to see
    # if it is inactive or not.
    DEPENDABOT_COST_EVENTS = %w(
      pull-request.created
    ).freeze

    # These are events which indicate a User is actively using Dependabot
    # and any inactivity monitoring should be suspended until there is
    # another cost event.
    ACTIVE_USER_EVENTS = %w(
      pull-request.reopened
      pull-request.merged
      pull-request.closed
      pull-request.comment
      repository.configuration-updated
      repository.configuration-updated.security-updates-enabled
      repository.configuration-deleted
      update-config.manual-version-update-requested
      update-config.manual-security-update-requested
    ).freeze

    # Some events may require additional checks before we act on them
    ACTIVE_USER_EVENT_FILTERS = {
      "pull-request.closed" => lambda { |_event_name, tags|
        tags[:"gh.actor.id"] != Dependabot::Application.github_dependabot_user_id
      },
    }.freeze

    def self.handle_activity_log_event(event_name, tags)
      return if event_name.starts_with?(ACTIVITY_MONITOR_CONTEXT) # ignore events this class emits
      return unless tags[:repository_id] # ignore events that don't relate to a Repository

      activity_manager = new(repo: Repo.find(tags[:repository_id]))
      if active_user_event?(event_name, tags)
        activity_manager.mark_as_active!(event_name)
      elsif dependabot_cost_event?(event_name)
        activity_manager.watch_for_inactivity!(event_name)
      end
    end

    private_class_method def self.active_user_event?(event_name, tags)
      return false unless ACTIVE_USER_EVENTS.include?(event_name)

      filter = ACTIVE_USER_EVENT_FILTERS[event_name]

      return true unless filter

      filter.call(event_name, tags)
    end

    private_class_method def self.dependabot_cost_event?(event_name)
      DEPENDABOT_COST_EVENTS.include?(event_name)
    end

    def initialize(repo:)
      @repo = repo
    end

    # Flags the Repository with a timestamp we expect to
    # see activity by, otherwise it will be paused.
    def watch_for_inactivity!(event_name)
      if repo.paused?
        activity_log.record_event("watched-for-inactivity.already_paused", tags: {
                                    triggered_by: event_name,
                                  })
        return
      end

      # Nothing to do if an earlier event has set this value
      return if repo.will_pause_at.present?

      repo.update(will_pause_at: pause_at_from_policy)

      activity_log.record_event("watched-for-inactivity", tags: {
                                  triggered_by: event_name,
                                })
    end

    # Clears the inactivity flag on a Repository so it is
    # no longer subject to being paused in future.
    def mark_as_active!(event_name)
      if repo.paused?
        repo.update!(will_pause_at: nil, paused_at: nil)

        AfterUnpauseRepoJob.perform_later(repo_id: repo.id)
        ResyncUnpausedRepoJob.perform_later(repo: repo)
        activity_log.record_event("marked-as-active", tags: { triggered_by: event_name, unpaused: true })
      elsif repo.will_pause_at.present?
        repo.update!(will_pause_at: nil, paused_at: nil)
        activity_log.record_event("marked-as-active", tags: { triggered_by: event_name, unpaused: false })
      end

      true
    end

    private

    def activity_log
      @activity_log ||= Activity::RepositoryLogger.new(
        repo: repo,
        context_name: ACTIVITY_MONITOR_CONTEXT
      )
    end

    def pause_at_from_policy
      return Time.now.utc if repo.config_feature_enabled?(:dependabot_paused_test_immediate)
      return 24.hours.from_now.utc if repo.config_feature_enabled?(:dependabot_paused_test_24_hours)

      90.days.from_now.utc
    end
  end
end
