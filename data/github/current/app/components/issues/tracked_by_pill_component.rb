# typed: true
# frozen_string_literal: true

module Issues
  class TrackedByPillComponent < ApplicationComponent
    def initialize(issue:, tracking_issues:)
      @issue = issue
      @tracking_issues = tracking_issues
    end

    def first_href_component
      issue_to_href(tracking_issue: @tracking_issues.first)
    end

    def issue_to_href(tracking_issue:)
      Issues::TrackedByHrefComponent.new(
        owner: tracking_issue[:owner],
        repository: tracking_issue[:repository],
        issue_number: tracking_issue[:issue_number],
        issue_title: tracking_issue[:issue_title],
        issue_url: tracking_issue[:issue_url],
        issue_state: tracking_issue[:issue_state],
        issue_state_reason: tracking_issue[:issue_state_reason],
        tracked_by_title: tracking_issue[:tracked_by_title],
        render_context: {
          current_owner: tracking_issue[:owner],
          current_repository: tracking_issue[:repository],
          hovercard_attributes: safe_data_attributes({
            "hovercard-type" => "tracking",
            "hovercard-url" => issue_path(tracking_issue[:owner], tracking_issue[:repository], tracking_issue[:issue_number]) + "/tracking/#{@issue.id}/hovercard"
          })
        }
      )
    end
  end
end
