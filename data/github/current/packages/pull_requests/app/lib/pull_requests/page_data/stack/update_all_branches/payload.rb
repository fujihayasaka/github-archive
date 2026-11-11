# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module UpdateAllBranches
        class Payload
          class PullRequestStatePayload < T::Struct
            const :number, Integer
            const :state, String
            const :message, T.nilable(String)
          end

          class PullRequestStatesData < T::Struct
            const :jobState, String
            const :pullRequestStates, T::Array[PullRequestStatePayload]
          end

          sig { params(data: T.nilable(Loader::Data)).returns(T.nilable(PullRequestStatesData)) }
          def self.call(data:)
            return if data.nil?
            new(data:).call
          end

          sig { params(data: Loader::Data).void }
          def initialize(data:)
            @data = data
          end

          sig { returns(PullRequestStatesData) }
          def call
            PullRequestStatesData.new(
              jobState: @data.job_state,
              pullRequestStates: @data.pull_request_states.map do |pr_state|
                PullRequestStatePayload.new(
                  number: pr_state.number,
                  state: pr_state.state,
                  message: pr_state.message,
                )
              end,
            )
          end
        end
      end
    end
  end
end
