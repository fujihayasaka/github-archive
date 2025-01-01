# typed: strict
# frozen_string_literal: true

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Content < T::Struct
          extend T::Sig

          const :id, Integer
          const :type, ContentType
          const :number, T.nilable(Integer)
          const :repository_id, T.nilable(Integer)

          prop :state, ContentState
          prop :state_reason, T.nilable(IssueStateReason)
          prop :is_draft, T::Boolean, default: false

          sig { returns(T::Hash[T.untyped, T.untyped]) }
          def to_hash
            {
              id: id,
              type: type.serialize,
              state: state.serialize,
              state_reason: state_reason&.serialize,
              is_draft: is_draft,
              number: number,
              repository_id: repository_id,
            }
          end

          sig { params(context: SeedContext).returns(Content) }
          def self.seed_elasticsearch_document(context)
            content_id = rand(1..1000)
            number = content_id + 1
            repository_id = content_id + 2

            case rand(1..6)
            when 1
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Open, number: number, repository_id: repository_id)
            when 2
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Closed, number: number, repository_id: repository_id)
            when 3
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Merged, number: number, repository_id: repository_id)
            when 4
              Content.new(id: content_id, type: ContentType::DraftIssue, state: DraftIssueState::Open, is_draft: true)
            when 5
              Content.new(id: content_id, type: ContentType::Issue, state: IssueState::Open, number: number, repository_id: repository_id)
            else
              reason = (
                case rand(1...4)
                when 1
                  IssueStateReason::NotPlanned
                when 2
                  IssueStateReason::Reopened
                when 3, 4
                  nil
                end
              )

              Content.new(id: content_id, type: ContentType::Issue, state: IssueState::Closed, state_reason: reason, number: number, repository_id: repository_id)
            end
          end
        end
      end
    end
  end
end
