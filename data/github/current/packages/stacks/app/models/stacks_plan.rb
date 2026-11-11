# typed: true
# frozen_string_literal: true

class StacksPlan < ApplicationRecord::Domain::Stacks # rubocop:todo GitHub/DatabaseModelsShouldHaveTests
  # rubocop:todo Rails/InverseOf
  has_many :stacks_flow, foreign_key: "plan_id",
    class_name: "StacksFlow", dependent: :destroy

  has_many :stacks_step, foreign_key: "plan_id",
    class_name: "StacksSteps::Step", dependent: :destroy

  has_many :stacks_status, foreign_key: "plan_id",
    class_name: "StacksStatus", dependent: :destroy
  # rubocop:enable Rails/InverseOf

  belongs_to :actor, class_name: "User"
  belongs_to :instance, class_name: "StacksInstance"

  def success?
    status == StacksStatus.statuses[:success]
  end

  def failed?
    status == StacksStatus.statuses[:failed]
  end

  def completed?
    success? || failed?
  end

  def in_progress?
    status == StacksStatus.statuses[:in_progress]
  end
end
