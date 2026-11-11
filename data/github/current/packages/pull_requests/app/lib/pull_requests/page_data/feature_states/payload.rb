# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module FeatureStates
      class Payload
        class FeatureStatesData < T::Struct
          const :overview, FeatureStates::Loader::State
          const :pullRequestStacks, FeatureStates::Loader::State
          const :pullRequestStacksPreventUnstackingLockedPrs, FeatureStates::Loader::State
        end

        sig { params(data: FeatureStates::Loader::Data).returns(FeatureStatesData) }
        def self.call(data:)
          new(data:).call
        end

        sig { params(data: FeatureStates::Loader::Data).void }
        def initialize(data:)
          @data = data
        end

        sig { returns(FeatureStatesData) }
        def call
          FeatureStatesData.new(
            overview: @data.overview,
            pullRequestStacks: @data.pull_request_stacks,
            pullRequestStacksPreventUnstackingLockedPrs: @data.pull_request_stacks_prevent_unstacking_locked_prs,
          )
        end
      end
    end
  end
end
