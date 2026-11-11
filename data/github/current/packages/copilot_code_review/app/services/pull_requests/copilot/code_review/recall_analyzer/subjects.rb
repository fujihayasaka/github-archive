# typed: strict
# frozen_string_literal: true

module PullRequests::Copilot::CodeReview::RecallAnalyzer
  # Allowlist of competitor review bot logins evaluated by RecallAnalyzer
  # in addition to Copilot Code Review.
  #
  # Each entry's user_id is the subject_user_id passed to
  # RecallAnalyzer::Analyzer. The analyzer measures, for a given subject,
  # "what did all other reviewers (humans + every other bot) catch that this
  # subject missed?" — see github/copilot-code-review#2588.
  #
  # Logins are resolved to User IDs at runtime so the module works across
  # environments (dev, review-lab, production, GHES). Any login that doesn't
  # resolve to a User (e.g., absent in a particular environment) is silently
  # skipped — callers receive only the subjects that exist in the current env.
  module Subjects
    # GitHub logins of the competitor review bots we evaluate alongside CCR.
    # Ranked by 30d comment volume in the `copilot_reviews_v0_comment_analysis`
    # Kusto table (queried 2026-06-08). All entries are general-purpose AI code
    # review products doing >=1K comments/month on dotcom PRs; non-review
    # tooling (security scanners, CI, monitoring) is intentionally excluded.
    # See github/copilot-code-review#2588.
    COMPETITOR_BOT_LOGINS = T.let(
      [
        "coderabbitai[bot]",
        "chatgpt-codex-connector[bot]",
        "cursor[bot]",
        "gemini-code-assist[bot]",
        "claude[bot]",
        "greptile-apps[bot]",
        "devin-ai-integration[bot]",
        "cubic-dev-ai[bot]",
        "augmentcode[bot]",
        "qodo-code-review[bot]",
        "amazon-q-developer[bot]",
        "anthropic-review[bot]",
        "sourcery-ai[bot]",
        "codeant-ai[bot]",
        "graphite-app[bot]",
      ].freeze,
      T::Array[String],
    )

    # Resolved competitor bot user_ids in the current environment.
    # Logins missing from the local User table are skipped. Resolved once
    # per process via a single WHERE-IN; bot accounts are stable for the
    # lifetime of a worker so we cache the result to avoid repeating the
    # lookup on every per-PR fan-out. Tests that mutate the User table
    # should call .reset_competitor_user_ids! in their setup hook.
    sig { returns(T::Array[Integer]) }
    def self.competitor_user_ids
      @competitor_user_ids ||= T.let(
        User.where(login: COMPETITOR_BOT_LOGINS).pluck(:id).freeze,
        T.nilable(T::Array[Integer]),
      )
    end

    # Clears the process-level cache. Intended for tests; production code
    # never needs to invalidate the cache.
    sig { void }
    def self.reset_competitor_user_ids!
      @competitor_user_ids = nil
    end
  end
end
