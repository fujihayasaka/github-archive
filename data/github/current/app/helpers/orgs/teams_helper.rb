# typed: true
# frozen_string_literal: true

module Orgs::TeamsHelper
  CHILD_INELIGIBILITY_REASONS = {
    "SECRET" => "Is a secret team",
    "ANCESTOR" => "Is an ancestor of this team",
    "PERMISSION" => "Request to move this team",
    "CHILD" => "Already a child of this team",
  }.freeze

  def child_ineligibility_reason(eligibility_status)
    CHILD_INELIGIBILITY_REASONS[eligibility_status]
  end
end
