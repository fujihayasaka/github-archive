# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module UpdateAllBranches
        class Loader
          class PullRequestStateData < T::Struct
            const :number, Integer
            const :state, String
            const :message, T.nilable(String)
          end

          class Data < T::Struct
            const :job_state, String
            const :pull_request_states, T::Array[PullRequestStateData]
          end

          sig { params(start_pull_request: PullRequest, repository: ::Repository).returns(T.nilable(Data)) }
          def self.load(start_pull_request:, repository:)
            new(start_pull_request:, repository:).load
          end

          sig { params(start_pull_request: PullRequest, repository: ::Repository).void }
          def initialize(start_pull_request:, repository:)
            @start_pull_request = start_pull_request
            @repository = repository
          end

          sig { returns(T.nilable(Data)) }
          def load
            stack = @start_pull_request.stack
            return nil if stack.nil?

            status = Stacks::UpdateAllBranches::Status.find(stack:)
            return nil if status.nil?

            pulls = stack.pulls_from(@start_pull_request)

            Data.new(
              job_state: status.job_state.serialize,
              pull_request_states: pulls.map do |pull|
                pr_state = status.for_pull_request(pull)

                PullRequestStateData.new(
                  number: pull.number,
                  state: state_name(pr_state),
                  message: state_message(pr_state),
                )
              end,
            )
          end

          private

          sig { params(pr_state: Stacks::UpdateAllBranches::Status::PullRequestState).returns(String) }
          def state_name(pr_state)
            case pr_state
            when Stacks::UpdateAllBranches::Status::PullRequestState::Succeeded then "SUCCEEDED"
            when Stacks::UpdateAllBranches::Status::PullRequestState::Failed then "FAILED"
            when Stacks::UpdateAllBranches::Status::PullRequestState::Conflicted then "CONFLICTED"
            when Stacks::UpdateAllBranches::Status::PullRequestState::Pending then "PENDING"
            else T.absurd(pr_state)
            end
          end

          sig { params(pr_state: Stacks::UpdateAllBranches::Status::PullRequestState).returns(T.nilable(String)) }
          def state_message(pr_state)
            case pr_state
            when Stacks::UpdateAllBranches::Status::PullRequestState::Failed then pr_state.message
            else nil
            end
          end
        end
      end
    end
  end
end
