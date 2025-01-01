# typed: true
# frozen_string_literal: true

class Issue::Adapter::LabelEventAdapter < Issue::Adapter::IssueEventAdapter
  LABELED_EVENT = "LabeledEvent"
  UNLABELED_EVENT = "UnlabeledEvent"

  attr_reader :label

  def initialize(context, event_id:, event_name:)
    super(context, event_id: event_id, event_name: event_name)

    raise "Invalid event name" if event_name != LABELED_EVENT && event_name != UNLABELED_EVENT
    label = context.labels_by_id[@issue_event.label_id]

    label ||= create_fake_label

    @label = Issue::Adapter::LabelAdapter.new(context, label: label)
  end

  private

  def create_fake_label
    # Using @context.repository here instead of @issue_event.repository id as the label is expected to exist
    # in the issue's current repo and it'll save us a potential query.
    # (Add `id: 0` becauase .global_relay_id needs _some_ kind of ID)
    ::Label.new(id: 0, name: @issue_event.label_name, color: @issue_event.label_color, repository: @context.repository)
  end

end
