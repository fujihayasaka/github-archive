# typed: false
# frozen_string_literal: true

class StacksStatus < ApplicationRecord::Domain::Stacks

  BATCH_SIZE = 100

  belongs_to :plan, class_name: "StacksPlan"
  belongs_to :instance, class_name: "StacksInstance"

  enum :entity_type, {
    flow: 0,
    step: 1
  }

  enum :status, {
    not_started: 0,
    in_progress: 1,
    success: 2,
    failed: 3
  }

  def self.insert_bulk_status_records(records)
    GitHub.tracer.in_span("#{self.class.name}##{__method__}", kind: :internal) do
      ActiveRecord::Base.connected_to(role: :writing) do
        records.each_slice(BATCH_SIZE) do |slice|
          throttle do
            insert_all(slice)
          end
        end
      end
    end
  end

  def self.update_entity_status(instance_id, entity_id, entity_type, entity_status)
    self.where(instance_id: instance_id)
        .where(entity_type: entity_type)
        .where(entity_id: entity_id)
        .update(status: entity_status)
  end

  def self.bulk_update_records_status(instance_id, entity_type, parent_id, from_status, to_status)
    self.where(instance_id: instance_id)
        .where(entity_type: entity_type)
        .where(parent_id: parent_id)
        .where(status: from_status)
        .update(status: to_status)
  end

  def self.fetch_step_status_records_for_flow(instance_id, flow_id)
    self.where(instance_id: instance_id)
        .where(entity_type: StacksStatus.entity_types[:step])
        .where(parent_id: flow_id)
  end

  def self.fetch_status_records_for_plan(instance_id, entity_type)
    self.where(instance_id: instance_id)
        .where(entity_type: entity_type)
  end

  def self.get_entity_status(instance_id, entity_type, entity_id)
    self.where(instance_id: instance_id)
        .where(entity_type: entity_type)
        .where(entity_id: entity_id)
        .first
        .status
  end
end
