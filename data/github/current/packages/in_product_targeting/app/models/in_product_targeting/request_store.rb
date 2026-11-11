# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Request-scoped storage for PageNudgeCoordinator instances (ADR Step 4).
  #
  # The ADR describes this as "request-scoped via RequestStore". The monolith
  # does not use the request_store gem, so this is backed by
  # ActiveSupport::CurrentAttributes — the codebase's idiomatic request-local
  # store — which the Rails executor resets between requests (and the test
  # harness resets between tests). Thread.current would leak state across
  # requests on threaded servers like Puma.
  #
  # Internal plumbing for PageNudgeCoordinator and SuppressionFlusher, kept
  # out of app/public deliberately: adopters never touch the store directly.
  class RequestStore < ActiveSupport::CurrentAttributes
    attribute :nudge_coordinators

    # The {[page, user_id] => PageNudgeCoordinator} map for the current
    # request, or nil when no coordinator has been stored yet. These two
    # accessors own the attribute's shape; consumers must not cast it
    # themselves.
    sig { returns(T.nilable(T::Hash[[Symbol, T.untyped], PageNudgeCoordinator])) }
    def self.coordinators
      T.cast(
        nudge_coordinators,
        T.nilable(T::Hash[[Symbol, T.untyped], PageNudgeCoordinator]),
      )
    end

    # Same map, initialized on first access — for PageNudgeCoordinator.for,
    # which is about to store one. Read-only paths (the suppression flush)
    # use `coordinators` instead, so a request that never built a coordinator
    # stays a nil check and allocates nothing.
    sig { returns(T::Hash[[Symbol, T.untyped], PageNudgeCoordinator]) }
    def self.coordinators!
      T.cast(
        self.nudge_coordinators ||= {},
        T::Hash[[Symbol, T.untyped], PageNudgeCoordinator],
      )
    end
  end
end
