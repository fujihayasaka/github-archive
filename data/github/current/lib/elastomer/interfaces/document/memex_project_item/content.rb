# typed: strict
# frozen_string_literal: true

require_relative "./timestamp_helper"

module Elastomer
  module Interfaces
    module Document
      module MemexProjectItem
        class Content < T::Struct
          include Elastomer::Interfaces::Document::MemexProjectItem::TimestampHelper

          const :id, Integer
          const :type, ContentType
          const :number, T.nilable(Integer)
          const :repository_id, T.nilable(Integer)
          const :user_id, T.nilable(Integer)
          const :closed_at, T.nilable(String)
          const :created_at, T.nilable(String)

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
              user_id: user_id,
              closed_at: safe_iso8601(closed_at),
              created_at: safe_iso8601(created_at),
            }
          end

          sig { params(context: SeedContext).returns(Content) }
          def self.seed_elasticsearch_document(context)
            content_id = rand(1..1000)
            number = content_id + 1
            repository_id = content_id + 2
            user_id = content_id + 3

            case rand(1..6)
            when 1
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Open, number: number, repository_id: repository_id, user_id: user_id)
            when 2
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Closed, number: number, repository_id: repository_id, user_id: user_id)
            when 3
              Content.new(id: content_id, type: ContentType::PullRequest, state: PullRequestState::Merged, number: number, repository_id: repository_id, user_id: user_id)
            when 4
              Content.new(id: content_id, type: ContentType::DraftIssue, state: DraftIssueState::Open, is_draft: true)
            when 5
              Content.new(id: content_id, type: ContentType::Issue, state: IssueState::Open, number: number, repository_id: repository_id, user_id: user_id)
            else
              reason = (
                case rand(1...4)
                when 1
                  IssueStateReason::NotPlanned
                when 2
                  IssueStateReason::Duplicate
                when 3
                  IssueStateReason::Reopened
                when 4
                  nil
                end
              )

              Content.new(id: content_id, type: ContentType::Issue, state: IssueState::Closed, state_reason: reason, number: number, repository_id: repository_id, user_id: user_id)
            end
          end
        end
      end
    end
  end
end
