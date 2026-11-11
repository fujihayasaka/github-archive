# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      module Overview
        class Payload
          class StackedPullRequest < T::Struct
            const :headBranch, String
            const :isUnstackable, T::Boolean
            const :number, Integer
            const :title, String
            const :state, String
            const :url, String
          end

          class StackInfo < T::Struct
            const :baseBranch, String
            const :id, Integer
            const :repositoryOwnerLogin, String
            const :repositoryName, String
            const :number, Integer
            const :position, Integer
            const :size, Integer
            const :allPullsLocked, T.nilable(T::Boolean)
            const :pulls, T::Array[StackedPullRequest]
          end

          class Root < T::Struct
            const :id, Integer
            const :stack, T.nilable(StackInfo)
          end

          sig { params(pull_request_id: Integer, data: T.nilable(Loader::StackData)).returns(Root) }
          def self.call(pull_request_id:, data:)
            new(pull_request_id:, data:).call
          end

          sig { params(pull_request_id: Integer, data: T.nilable(Loader::StackData)).void }
          def initialize(pull_request_id:, data:)
            @pull_request_id = pull_request_id
            @data = data
          end

          sig { returns(Root) }
          def call
            Root.new(
              id: @pull_request_id,
              stack: serialize_stack(@data),
            )
          end

          private

          sig { params(data: T.nilable(Loader::StackData)).returns(T.nilable(StackInfo)) }
          def serialize_stack(data)
            return nil if data.nil?

            StackInfo.new(
              baseBranch: data.base_branch,
              id: data.id,
              repositoryOwnerLogin: data.repository_owner_login,
              repositoryName: data.repository_name,
              number: data.number,
              position: data.position,
              size: data.size,
              allPullsLocked: data.all_pulls_locked,
              pulls: data.pulls.map do |pull_data|
                StackedPullRequest.new(
                  headBranch: pull_data.head_branch,
                  isUnstackable: pull_data.is_unstackable,
                  number: pull_data.number,
                  title: pull_data.title,
                  state: pull_data.state,
                  url: pull_data.url,
                )
              end,
            )
          end
        end
      end
    end
  end
end
