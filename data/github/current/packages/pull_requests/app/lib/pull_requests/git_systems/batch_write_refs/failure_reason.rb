# typed: strict
# frozen_string_literal: true

module PullRequests
  module GitSystems
    # Batching class for doing ref updates that conform to branch rules/protections.
    module BatchWriteRefs
      class FailureReason < T::Enum
        enums do
          # TODO: This will become exhaustive once we build out the batch ref updating service.
          BranchRule = new(:branch_rule)
          RefUpdateFailed = new(:ref_update)
        end
      end
    end
  end
end
