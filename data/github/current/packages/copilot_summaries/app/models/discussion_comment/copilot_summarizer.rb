# typed: strict
# frozen_string_literal: true

class DiscussionComment::CopilotSummarizer
  include GitHub::Memoizer

  sig { params(markdown: T.nilable(String), repository: T.nilable(Repository)).returns(String) }
  def self.process_markdown_for_summarization(markdown, repository:)
    # Do the same processing on discussion comment text as we do for the main discussion body.
    Discussion::CopilotSummarizer.process_markdown_for_summarization(markdown, repository: repository)
  end

  sig { params(comment: DiscussionComment, actor: User).void }
  def initialize(comment:, actor:)
    @comment = comment
    @actor = actor
  end

  # Public: Returns a Hash that fits the shape of `DiscussionComment` type in copilot-api.
  # https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L29-L37
  sig { returns T::Hash[Symbol, T.untyped] }
  def copilot_api_reference_data
    {
      author: author_display_login,
      body: body_text,
      createdAt: created_at&.utc&.iso8601,
      totalUpvotes: total_upvotes,
      reactionCounts: reaction_counts_for_copilot_api,
    }
  end

  sig { returns Integer }
  def body_length
    body_text.length
  end

  private

  sig { returns DiscussionComment }
  attr_reader :comment

  sig { returns User }
  attr_reader :actor

  # Private: Returns a list of reaction counts to suit the structure of the `ReactionCounts` field in the
  # `DiscussionComment` type in copilot-api. https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L36
  sig { returns T::Array[T::Hash[Symbol, T.any(String, Integer)]] }
  def reaction_counts_for_copilot_api
    reactions_count.map do |reaction, count|
      # https://github.com/github/copilot-api/blob/e28abf0fe94107f4ccad13708c2c2407bc89756b/pkg/chat/reference/discussion.go#L23-L27
      { reaction: reaction, count: count }
    end
  end

  sig { returns String }
  memoize def body_text
    self.class.process_markdown_for_summarization(body, repository: repository)
  end

  sig { returns(String) }
  def body
    comment.body || ""
  end

  sig { returns(Integer) }
  def total_upvotes
    comment.total_upvotes
  end

  sig { returns(String) }
  def author_display_login
    comment.author_display_login
  end

  sig { returns T.nilable(ActiveSupport::TimeWithZone) }
  def created_at
    comment.created_at
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
