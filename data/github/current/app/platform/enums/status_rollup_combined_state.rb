# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    # This class maps 1:1 with the status_checks_serializer StatusRollupCombinedState to a GQL enum.
    # @see packages/pull_requests/app/lib/pull_requests/page_data/status_checks_serializer.rb
    class StatusRollupCombinedState < Platform::Enums::Base
      description "The possible combined states of a commit."

      required_capabilities [:mobile_only_schema_mask]

      value "FAILED", "The check run has failed.", value: "failed"
      value "PASSED", "The check run has passed.", value: "passed"
      value "PENDING", "The check run is pending.", value: "pending"
      value "PENDING_APPROVAL", "The check run is pending approval.", value: "pending_approval"
      value "PENDING_FAILED", "The check run is pending but has failed.", value: "pending_failed"
      value "SOME_FAILED", "Some check runs have failed.",  value: "some_failed"
    end
  end
end
