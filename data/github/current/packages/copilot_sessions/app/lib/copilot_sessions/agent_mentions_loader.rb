# typed: strict
# frozen_string_literal: true

module CopilotSessions
  class AgentMentionsLoader
    sig { params(pull_request: PullRequest, comment_ids: T::Array[Integer], review_ids: T::Array[Integer]).void }
    def initialize(pull_request:, comment_ids: [], review_ids: [])
      @pull_request = pull_request
      @comment_ids = comment_ids
      @review_ids = review_ids
    end

    sig { returns(T::Hash[Integer, CopilotSessions::Payloads::AgentMention::AgentMentionHash]) }
    def comment_mentions_by_id
      return {} if @comment_ids.empty?

      issue = @pull_request.issue
      return {} if issue.nil?

      issue.comments
        .includes(:user)
        .where(id: @comment_ids)
        .order(:created_at)
        .to_h do |comment|
          [
            comment.id,
            CopilotSessions::Payloads::AgentMention.from_issue_comment(comment, @pull_request)
          ]
        end
    end

    sig { returns(T::Hash[Integer, CopilotSessions::Payloads::AgentMention::AgentMentionHash]) }
    def review_mentions_by_id
      return {} if @review_ids.empty?

      @pull_request.reviews
        .includes(:user, review_comments: :pull_request_review_thread)
        .where(id: @review_ids)
        .order(:created_at)
        .to_h do |review|
          [
            review.id,
            CopilotSessions::Payloads::AgentMention.from_review(review, @pull_request)
          ]
        end
    end

    sig { returns(T::Array[CopilotSessions::Payloads::AgentMention::AgentMentionHash]) }
    def load_all
      comment_mentions_by_id.values + review_mentions_by_id.values
    end
  end
end
