# typed: true
# frozen_string_literal: true

module DependencyGraph
  class SnapshotStatusComponent < ApplicationComponent
    include GitHub::ResilienceMixin

    DEPENDABOT_DETECTOR_NAME = "dependabot"

    READY_REASONS = %i[
      DEPENDABOT_READINESS_REASON_SNAPSHOT_COMPLETE
    ].freeze

    PARTIAL_REASONS = %i[
      DEPENDABOT_READINESS_REASON_DEADLINE_PAST_PARTIAL_SNAPSHOT
      DEPENDABOT_READINESS_REASON_DEADLINE_PAST_NO_SNAPSHOT
    ].freeze

    OK_STATUSES = %i[JOB_STATUS_OK JOB_STATUS_SKIPPED].freeze
    DEGRADED_STATUSES = %i[JOB_STATUS_DEGRADED].freeze
    FAILED_STATUSES = %i[JOB_STATUS_FAILED JOB_STATUS_UNSPECIFIED].freeze

    COMMIT_PREFIX = GitHub::HTMLSafeString.make(" for commit ")
    REFRESH_PREFIX = GitHub::HTMLSafeString.make("Fixed the issue? ")

    # @param repository [Repository] The current repository.
    # @param owner [User, Organization] The repository owner.
    # @param last_content_scan_at [Time, nil] Fallback timestamp from VulnerabilityAlertingEvent.
    # @param snapshot_metadata [Array] Repeated SnapshotMetadata proto messages from DG-API.
    def initialize(repository:, owner:, last_content_scan_at:, snapshot_metadata:)
      @repository = repository
      @owner = owner
      @last_content_scan_at = last_content_scan_at
      @snapshot_metadata = snapshot_metadata || []
    end

    def render?
      readiness_state.present? || aggregate_status.present?
    end

    def pending?
      readiness_state&.dig(:status) == :pending
    end

    def checked_at
      readiness_state&.dig(:time)
    end

    def status_pip
      color = if pending?
        :muted
      else
        case aggregate_status
        when :success then :success
        when :attention then :attention
        when :danger then :danger
        end
      end

      return GitHub::HTMLSafeString::EMPTY unless color

      render Primer::Beta::Octicon.new(icon: "dot-fill", color:, mr: 1, test_selector: "snapshot-status-pip")
    end

    def error_count_text
      count = problematic_job_ids.size
      if aggregate_status == :attention
        "#{count} #{'warning'.pluralize(count)}"
      else
        "#{count} #{'error'.pluralize(count)}"
      end
    end

    def degraded_or_errored?
      aggregate_status.in?([:attention, :danger])
    end

    def workflow_url
      Rails.application.routes.url_helpers.network_dependency_status_path(@owner, @repository)
    end

    def commit_suffix
      return GitHub::HTMLSafeString::EMPTY unless commit_sha && commit_url

      COMMIT_PREFIX + link_to(commit_sha[0, 7], commit_url, class: "Link--inTextBlock")
    end

    def refresh_message
      return GitHub::HTMLSafeString::EMPTY unless show_refresh_link?

      if refresh_on_cooldown?
        content_tag(:span, "Dependency graph refresh requested recently, available again in #{distance_of_time_in_words_to_now(cooldown_ends_at)}.", class: "color-fg-muted")
      else
        REFRESH_PREFIX + link_to("Refresh the dependency graph.", refresh_graph_path, class: "Link--inTextBlock")
      end
    end

    private

    def commit_sha
      readiness_state&.dig(:sha)
    end

    def commit_url
      readiness_state&.dig(:commit_url)
    end

    def show_refresh_link?
      GitHub.dependency_graph_enabled? &&
        SecurityProduct::Permissions::RepoAuthz.new(@repository, actor: current_user).can_manage_repo_security_products?
    end

    def refresh_on_cooldown?
      data_refresh_manager.on_cooldown?
    end

    def cooldown_ends_at
      data_refresh_manager.cooldown_ends_at
    end

    def refresh_graph_path
      Rails.application.routes.url_helpers.refresh_dependency_graph_path(@owner, @repository)
    end

    memoize def readiness_state
      fetch_readiness_state
    end

    # Returns :success, :attention, :danger, or nil (when no Dependabot metadata present).
    memoize def aggregate_status
      dependabot_metadata = @snapshot_metadata.select do |m|
        m.detector_name&.casecmp?(DEPENDABOT_DETECTOR_NAME)
      end

      return nil if dependabot_metadata.empty?

      if dependabot_metadata.any? { |m| FAILED_STATUSES.include?(m.status) }
        :danger
      elsif dependabot_metadata.any? { |m| DEGRADED_STATUSES.include?(m.status) }
        :attention
      else
        :success
      end
    end

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
        ready_state(event)
      else
        fallback_state
      end
    rescue DependencySnapshot::NotFoundError
      fallback_state
    rescue DependencySnapshot::Error, Faraday::Error => e
      Failbot.report(e)
      fallback_state
    end

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
      sha = event&.sha

      {
        status: :pending,
        sha:,
        commit_url: sha ? "/#{@repository.name_with_display_owner}/commit/#{sha}" : nil,
      }
    end

    def ready_state(event)
      sha = event&.sha
      timestamp = event&.created_at
      time = if timestamp.respond_to?(:to_time)
        timestamp.to_time
      else
        timestamp
      end

      {
        status: :ready,
        time: time || @last_content_scan_at,
        sha:,
        commit_url: sha ? "/#{@repository.name_with_display_owner}/commit/#{sha}" : nil,
      }
    end

    memoize def data_refresh_manager
      DependencyGraph::DataRefreshManager.new(@repository)
    end

    memoize def problematic_job_ids
      ids = @snapshot_metadata.filter_map do |m|
        next unless m.detector_name&.casecmp?(DEPENDABOT_DETECTOR_NAME)
        next if OK_STATUSES.include?(m.status)

        m.job_id
      end
      ids.uniq
    end
  end
end
