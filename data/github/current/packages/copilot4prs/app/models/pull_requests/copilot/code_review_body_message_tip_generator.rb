# typed: strict
# frozen_string_literal: true

module PullRequests::Copilot
  class CodeReviewBodyMessageTipGenerator
    class CodeReviewBodyMessageTip
      Pred = T.type_alias do
        T.proc.params(arg0: PullRequest, arg1: Repository, arg2: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Boolean)
      end
      DEFAULT_PROC = T.let(->(_, _, _) { true }, Pred)
      sig { params(msg: String, blk: T.nilable(Pred)).void }
      def initialize(msg, &blk)
        @msg = T.let(msg, String)
        @conditional = T.let(blk || DEFAULT_PROC, Pred)
      end

      sig do
        params(
          pull: PullRequest,
          repo: Repository,
          comments: T::Array[T::Hash[T.untyped, T.untyped]]).returns(T::Boolean)
      end
      def match(pull, repo, comments)
        @conditional.call(pull, repo, comments)
      end

      sig { returns(String) }
      def to_s
        @msg
      end
    end
    Tip = CodeReviewBodyMessageTip

    LANGUAGES = "Copilot code review supports C#, Go, Java, JavaScript, Markdown, Python, Ruby and TypeScript, with more languages coming soon."
    CONFIDENCE = "Copilot only keeps its highest confidence comments to reduce noise and keep you focused."
    WITH_COMMENTS = "Leave feedback on Copilot's review comments with the 👎 and 👍 buttons to help improve review quality."
    AUTO_REVIEWS = "Turn on automatic Copilot reviews for this repository to get quick feedback on every pull request."
    VS_CODE = "If you use Visual Studio Code, you can request a review from Copilot before you push from the \"Source Control\" tab."

    TIPS = T.let([
      Tip.new(LANGUAGES),
      Tip.new(CONFIDENCE),
      Tip.new(WITH_COMMENTS) { |_, _, comments| comments.any? },
      Tip.new(VS_CODE) { GitHub.flipper[:copilot_code_review_vs_code_tip].enabled? },
      Tip.new(AUTO_REVIEWS) do |pull, repo|
        !(T.cast(
          pull.base_branch_rule_evaluator&.automatic_copilot_code_review_enabled? ||
          repo.feature_enabled_for_repo_or_owner?(:copilot_reviews_automatic_pull_request_review),
        T.nilable(T::Boolean)))
      end,
    ], T::Array[CodeReviewBodyMessageTip])

    LEARN_MORE = "[Learn more](https://gh.io/copilot-code-reviews-docs)"

    sig do
      params(
        pull: PullRequest,
        repo: Repository,
        comments: T::Array[T::Hash[T.untyped, T.untyped]]).returns(String)
    end
    def self.tip_for(pull, repo, comments)
      tips = TIPS.select { _1.match(pull, repo, comments) }
      "**Tip:** #{tips.sample}  #{LEARN_MORE}"
    end
  end
end
