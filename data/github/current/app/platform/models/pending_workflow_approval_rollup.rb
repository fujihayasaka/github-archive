# typed: true
# frozen_string_literal: true

class Platform::Models::PendingWorkflowApprovalRollup
  attr_reader :repository, :workflows_pending_approval

  def initialize(repository:, workflows_pending_approval: nil)
    @repository = repository
    @workflows_pending_approval = workflows_pending_approval
  end
end
