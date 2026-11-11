# typed: true
# frozen_string_literal: true

class Issue::Adapter::RenameEventAdapter < Issue::Adapter::IssueEventAdapter
  RENAMED_TITLE_EVENT = "RenamedTitleEvent"
  RENAMED_EVENT = "RenamedEvent"

  attr_reader :previous_title, :current_title

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: RENAMED_EVENT)

    @previous_title = @issue_event.title_was
    @current_title = @issue_event.title_is
    # This is a deviation from our pattern, because we have a 'renamed' event
    # which is internally refered to as 'RenamedTitleEvent'.
    # see https://github.com/github/github/blob/bcf8caf2bc57932b23beb9ad376c528549dd4b81/app/helpers/issue_events_helper.rb#L7
    @id = @issue_event.global_relay_id
  end
end
