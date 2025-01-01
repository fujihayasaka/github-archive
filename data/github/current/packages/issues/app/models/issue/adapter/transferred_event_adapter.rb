# typed: true
# frozen_string_literal: true

class Issue::Adapter::TransferredEventAdapter < Issue::Adapter::IssueEventAdapter
  TRANSFERRED_EVENT = "TransferredEvent"

  attr_reader :from_repository

  def initialize(context, event_id:)
    super(context, event_id: event_id, event_name: TRANSFERRED_EVENT)
    repository = @context.readable_repositories_by_id[@issue_event.subject_id]
    @from_repository = repository && Issue::Adapter::TransferredEventFromRepositoryAdapter.new(context, repository: repository)
  end
end
