# typed: true
# frozen_string_literal: true

module Issues
  class TrackedInComponent < ApplicationComponent

    def initialize(tracked_in_issues:, current_issue_owner:, current_issue_repository:)
      @tracked_in_issues = tracked_in_issues
      @current_issue_owner = current_issue_owner
      @current_issue_repository = current_issue_repository
    end

    def render?
      @tracked_in_issues.present? &&
      @current_issue_owner.present? &&
      @current_issue_repository.present?
    end

    def components
      tracked_in_issues_by_state = @tracked_in_issues.group_by { |tracked_in_issue| tracked_in_issue[:issue_state].upcase.to_sym }
      components = [:OPEN, :CLOSED].map do |state|
        tracked_in_issues_by_state[state]&.map do |tracked_in_issue|
          Issues::IssueHrefComponent.new(
            owner: tracked_in_issue[:owner],
            repository: tracked_in_issue[:repository],
            issue_number: tracked_in_issue[:issue_number],
            issue_url: tracked_in_issue[:issue_url],
            issue_state: tracked_in_issue[:issue_state],
            issue_state_reason: tracked_in_issue[:issue_state_reason],
            render_context: {
              current_owner: @current_issue_owner,
              current_repository: @current_issue_repository,
              style_link_normal: true,
            }
          )
        end
      end

      components.flatten(1).compact
    end
  end
end
