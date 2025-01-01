# typed: true
# frozen_string_literal: true

class PullRequest
  class ChannelEventBuilder
    def initialize(pull, associated_updates = {})
      @pull = pull
      @associated_updates = associated_updates
    end

    def build_payload
      issue_changes = @pull.issue.previous_changes # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      previous_pull_changes = @pull.previous_changes
      payload = { event_updates: {} }

      payload[:event_updates][:title_updated] = title_updated?(issue_changes, previous_pull_changes)
      payload[:event_updates][:git_updated] = previous_pull_changes.include?("base_sha") || previous_pull_changes.include?("head_sha")

      if issue_changes.include?("compressed_body")
        payload[:event_updates][:body_updated] = true
      else
        # changing the PR body does not add an item to the timeline
        # so we do not need to re-render the timeline partial
        payload[:event_updates][:timeline_updated] = true
      end

      if update_entire_sidebar?(payload)
        payload[:event_updates][:sidebar_updated] = true
      else
        payload[:event_updates].merge!(@associated_updates)
      end

      # Remove any false values from the payload
      payload[:event_updates].reject! { |_, v| v == false }

      payload
    end

    private

    def update_entire_sidebar?(payload)
      return false if repository.feature_enabled?(:skip_full_sidebar_updates)

      !links_should_be_updated?(payload) && @associated_updates.empty?
    end

    def links_should_be_updated?(payload)
      repository.feature_enabled?(:links_event_updates) && payload.dig(:event_updates, :body_updated)
    end

    def title_updated?(issue_changes, previous_pull_changes)
      issue_changes.include?("title") ||
        previous_pull_changes.include?("merged_at") ||
          previous_pull_changes.include?("work_in_progress")
    end

    sig { returns(Repository) }
    def repository = T.must(@pull.repository)
  end
end
