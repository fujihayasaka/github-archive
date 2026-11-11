# typed: true
# frozen_string_literal: true

class Platform::Models::StatusRollup
  attr_reader :repository, :status_checks, :workflows_pending_approval

  def initialize(repository:, status_checks:, workflows_pending_approval: nil)
    @repository = repository
    @status_checks = status_checks
    @workflows_pending_approval = workflows_pending_approval
  end
end
