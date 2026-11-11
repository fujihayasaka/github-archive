# typed: true
# frozen_string_literal: true

class Issue::Adapter::MemexProjectEventAdapter < Issue::Adapter::IssueEventAdapter
  attr_reader :memex_title, :memex_resource_path

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)
    @memex_title = memex.title
    @memex_resource_path = memex.url
  end

  def memex
    context.memexes_by_id[@issue_event.project_id]
  end
end
