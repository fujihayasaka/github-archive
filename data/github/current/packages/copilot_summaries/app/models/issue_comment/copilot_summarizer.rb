# typed: strict
# frozen_string_literal: true

class IssueComment::CopilotSummarizer
  include GitHub::Memoizer

  sig { params(markdown: T.nilable(String), repository: T.nilable(Repository)).returns(String) }
  def self.process_markdown_for_summarization(markdown, repository:)
    # Do the same processing on issue comment text as we do for the main issue body.
    Issue::CopilotSummarizer.process_markdown_for_summarization(markdown, repository: repository)
  end

  sig { params(comment: IssueComment, actor: User).void }
  def initialize(comment:, actor:)
    @comment = comment
    @actor = actor
  end

  # Public: Returns a Hash that fits the shape of `IssueComment` type in copilot-api.
  # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L24-L30
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference_data
    {
      author: safe_user.display_login,
      body: body_text,
      createdAt: created_at&.utc&.iso8601,
      reactionCounts: reaction_counts_for_copilot_api,
    }
  end

  sig { returns Integer }
  def body_length
    body_text.length
  end

  private

  sig { returns IssueComment }
  attr_reader :comment

  sig { returns User }
  attr_reader :actor

  sig { returns String }
  memoize def body_text
    self.class.process_markdown_for_summarization(body, repository: repository)
  end

  # Private: Returns a list of reaction counts to suit the structure of the `ReactionCounts` field in the
  # `IssueComment` type in copilot-api.
  # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L56
  sig { returns T::Array[T::Hash[Symbol, T.any(String, Integer)]] }
  def reaction_counts_for_copilot_api
    reactions_count.map do |reaction, count|
      # https://github.com/github/copilot-api/blob/9f0fb30b7c44be31f17ad762a64d35cbb9fed93b/pkg/chat/reference/issue.go#L18-L22
      { reaction: reaction, count: count }
    end
  end

  sig { returns T.nilable(ActiveSupport::TimeWithZone) }
  def created_at
    comment.created_at
  end

  sig { returns User }
  def safe_user
    comment.safe_user
  end

  sig { returns(String) }
  def body
    comment.body || ""
  end

  sig { returns T::Hash[String, Integer] }
  def reactions_count
    comment.reactions_count
  end

  sig { returns(T.nilable(Repository)) }
  def repository
    comment.repository
  end
end
