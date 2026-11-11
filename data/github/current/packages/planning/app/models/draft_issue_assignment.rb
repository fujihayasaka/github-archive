# typed: true
# frozen_string_literal: true

class DraftIssueAssignment < ApplicationRecord::Domain::Memexes # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  include ContextualActor
  include Instrumentation::Model

  # todo: remove this after the table has been renamed
  self.table_name = "issue_next_assignments"

  ON_CREATE_INSTRUMENTATION_KEY = "draft_issue.assignment.create"
  ON_DESTROY_INSTRUMENTATION_KEY = "draft_issue.assignment.destroy"

  belongs_to :target, polymorphic: true
  belongs_to :assignee, class_name: "User"

  before_destroy :generate_draft_issue_unassigned_webhook_payload
  after_commit :queue_draft_issue_unassigned_webhook_delivery, on: :destroy
  after_commit :instrument_create_event, on: :create
  after_commit :instrument_create_event_for_hydro, on: :create
  after_commit :instrument_destroy_event_for_hydro, on: :destroy

  def event_payload
    return unless target_type == DraftIssue.name
    target&.unassigned_webhook_event_payload
  end

  def generate_draft_issue_unassigned_webhook_payload
    return unless target_type == DraftIssue.name
    return unless (complete_payload = event_payload)
    @future_webhook_delivery = Hook::DeliverySystem
      .new(Hook::Event::ProjectsV2ItemEvent.new(**complete_payload))
      .tap(&:generate_hookshot_payloads)
  end

  def queue_draft_issue_unassigned_webhook_delivery
    return unless defined?(@future_webhook_delivery)
    @future_webhook_delivery.deliver_later
    remove_instance_variable(:@future_webhook_delivery)
  end

  private def instrument_create_event
    return unless event_payload
    instrument :create
  end

  private def instrument_create_event_for_hydro
    GlobalInstrumenter.instrument(ON_CREATE_INSTRUMENTATION_KEY,
      target.hydro_assignee_payload
    )
  end

  private def instrument_destroy_event_for_hydro
    return unless target
    GlobalInstrumenter.instrument(ON_DESTROY_INSTRUMENTATION_KEY,
      target.hydro_assignee_payload.merge(
        previous_assignee: self.assignee
      )
    )
  end
end
