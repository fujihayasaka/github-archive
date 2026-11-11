# typed: strict
# frozen_string_literal: true

module PullRequests
  module PageData
    module Stack
      class Payload
        class StackedPullRequestData < T::Struct
          const :isUnstackable, T::Boolean
          const :title, String
          const :number, Integer
          const :state, String
          const :url, String
          const :headBranch, String
          const :headOid, String
        end

        class StackData < T::Struct
          const :id, Integer
          const :baseBranch, String
          const :repositoryOwnerLogin, String
          const :repositoryName, String
          const :number, Integer
          const :position, Integer
          const :size, Integer
          const :allPullsLocked, T.nilable(T::Boolean)
          const :pulls, T::Array[StackedPullRequestData]
        end

        sig { params(data: T.nilable(Stack::Loader::Data)).returns(T.nilable(StackData)) }
        def self.call(data:)
          return if data.nil?
          new(data:).call
        end

        sig { params(data: Stack::Loader::Data).void }
        def initialize(data:)
          @data = data
        end

        sig { returns(StackData) }
        def call
          StackData.new(
            id: @data.id,
            baseBranch: @data.base_branch,
            repositoryOwnerLogin: @data.repository_owner_login,
            repositoryName: @data.repository_name,
            number: @data.number,
            position: @data.position,
            size: @data.size,
            allPullsLocked: @data.all_pulls_locked,
            pulls: @data.pulls.map do |pull_data|
              StackedPullRequestData.new(
                isUnstackable: pull_data.is_unstackable,
                title: pull_data.title,
                number: pull_data.number,
                state: pull_data.state,
                url: pull_data.url,
                headBranch: pull_data.head_branch,
                headOid: pull_data.head_oid,
              )
            end
          )
        end
      end
    end
  end
end
