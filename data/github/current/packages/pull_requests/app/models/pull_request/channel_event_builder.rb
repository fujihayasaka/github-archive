# typed: true
# frozen_string_literal: true

class PullRequest
  class ChannelEventBuilder
    def initialize(pull, associated_updates = {})
      @pull = pull
      @associated_updates = associated_updates
    end

    def build_payload
      issue_changes = @pull.issue.previous_changes
      previous_pull_changes = @pull.previous_changes
      payload = { event_updates: {} }

      if issue_changes.include?("title")
        payload[:event_updates][:title_updated] = true
      end

      if issue_changes.include?("compressed_body")
        payload[:event_updates][:body_updated] = true
      end

      payload[:event_updates][:git_updated] = previous_pull_changes.include?("base_sha") || previous_pull_changes.include?("head_sha")

      # changing the PR body does not add an item to the timeline
      # so we do not need to re-render the timeline partial
      if !issue_changes.include?("compressed_body")
        payload[:event_updates][:timeline_updated] = true
      end

      if previous_pull_changes.include?("merged_at") || previous_pull_changes.include?("work_in_progress")
        payload[:event_updates][:title_updated] = true
      end

      if @pull&.repository&.feature_enabled?(:sidebar_event_updates)
        if update_entire_sidebar?(payload)
          payload[:event_updates][:sidebar_updated] = true
        else
          payload[:event_updates].merge!(@associated_updates)
        end
      end

      payload
    end

    def update_entire_sidebar?(payload)
      !links_should_be_updated?(payload) && @associated_updates.empty?
    end

    def links_should_be_updated?(payload)
      @pull&.repository&.feature_enabled?(:links_event_updates) && payload.dig(:event_updates, :body_updated)
    end
  end
end
