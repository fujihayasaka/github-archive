# typed: true
# frozen_string_literal: true

class StacksFlow < ApplicationRecord::Domain::Stacks
  BATCH_SIZE = 100

  belongs_to :plan, class_name: "StacksPlan"
  belongs_to :instance, class_name: "StacksInstance"

  belongs_to :depends_on, class_name: "StacksFlow", foreign_key: "depends_on" # rubocop:todo Rails/InverseOf

  # rubocop:todo Rails/InverseOf
  has_many :stacks_step, foreign_key: "flow_id",
    class_name: "StacksSteps::Step"
  # rubocop:enable Rails/InverseOf

  def self.insert_bulk_flow_records(records)
    ActiveRecord::Base.connected_to(role: :writing) do
      records.each_slice(BATCH_SIZE) do |slice|
        throttle do
          insert_all(slice)
        end
      end
    end
  end

  def self.get_dependant_flows(instance_id, id)
    self.where(instance_id: instance_id)
        .where(depends_on: id)
  end
end
