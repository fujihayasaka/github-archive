# typed: true
# frozen_string_literal: true

module DependabotAlerts
  class ReadinessSubheadComponent < ApplicationComponent
    include GitHub::ResilienceMixin

    READY_REASONS = %i[
      DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE
    ].freeze

    PARTIAL_REASONS = %i[
      DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT
      DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT
    ].freeze

    # @param repository [Repository] The current repository.
    # @param last_content_scan_at [Time, nil] Fallback timestamp from VulnerabilityAlertingEvent.
    def initialize(repository:, last_content_scan_at:)
      @repository = repository
      @last_content_scan_at = last_content_scan_at
    end

    memoize def readiness_state
      fetch_readiness_state
    end

    private

    def fetch_readiness_state
      response = DependencySnapshot::DependabotReadinessClient.new.check_repository_readiness(
        repository_id: @repository.id,
      )

      event = response&.most_recent_event
      reason = response&.reason

      if reason == :DEPENDABOT_READINESS_REASON_PENDING
        pending_state(event)
      elsif READY_REASONS.include?(reason) && event
        ready_state(event)
      elsif PARTIAL_REASONS.include?(reason) && event
        partial_state(event)
      else
        fallback_state
      end
    rescue DependencySnapshot::NotFoundError
      fallback_state
    rescue DependencySnapshot::Error, Faraday::Error => e
      # Notice any failures, but don't block page load
      Failbot.report(e)
      fallback_state
    end

    # NOTE: This fallback state is required until Dependabot snapshots all ecosystems
    #
    # DS-API only tracks readiness events for pushes where at least one snapshot is requested,
    # for now we should fallback to the existing behaviour when no event is present or something
    # goes wrong checking state.
    def fallback_state
      return nil unless @last_content_scan_at

      {
        status: :fallback,
        time: @last_content_scan_at,
        sha: nil,
        commit_url: nil,
      }
    end

    def pending_state(event)
      sha = event_sha(event)

      {
        status: :pending,
        sha:,
        commit_url: sha ? "/#{@repository.name_with_display_owner}/commit/#{sha}" : nil,
      }
    end

    def ready_state(event)
      sha = event_sha(event)

      {
        status: :ready,
        time: event_created_at(event) || @last_content_scan_at,
        sha:,
        commit_url: sha ? "/#{@repository.name_with_display_owner}/commit/#{sha}" : nil,
      }
    end

    def partial_state(event)
      sha = event_sha(event)

      {
        status: :partial,
        time: event_created_at(event) || @last_content_scan_at,
        sha:,
        commit_url: sha ? "/#{@repository.name_with_display_owner}/commit/#{sha}" : nil,
        workflow_url: dependency_graph_workflow_url,
      }
    end

    def event_sha(event)
      event&.sha
    end

    def event_created_at(event)
      timestamp = event&.created_at
      return nil unless timestamp

      timestamp.respond_to?(:to_time) ? timestamp.to_time : timestamp
    end

    def dependency_graph_workflow_url
      "/#{@repository.name_with_display_owner}/actions/workflows/dependabot/update-graph"
    end
  end
end
