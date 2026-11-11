# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Rack middleware that flushes buffered nudge-suppression telemetry
  # (PageNudgeCoordinator, ADR "Cross-Surface Nudge Priority Coordination"
  # Step 7) at the end of each request.
  #
  # This is the unit-tested entry point for the flush behaviour. Production does
  # not mount this class directly: the middleware stack is built at boot, before
  # this package is autoloadable, so the boot-safe IpmSuppressionFlushAdapter
  # (see the package initializer) is registered instead, resolving the package
  # lazily at request time (dotcom only — the framework excludes GHES and
  # Proxima). Both this class and the adapter delegate to the single shared body
  # SuppressionFlusher.flush_after, so the tested path is the production path and
  # the two cannot drift.
  #
  # The flush runs only when the inner app returns normally: while an exception
  # is unwinding the page never rendered, so flushing would emit
  # suppression/orphan events for failed requests and inflate the orphaned
  # signal with 500s. The unsent buffer is discarded with the rest of the
  # request store by the Rails executor.
  #
  # ASSUMPTION: no coordinated page streams its response body. The flush runs
  # when the inner app returns, before a streaming body (ActionController::Live,
  # send_stream) is produced, so a confirm_render! fired while streaming would
  # land after the flush and its losers would be mis-reported as orphaned. Until
  # a hard guard exists, a streaming surface must not be onboarded; the
  # SuppressionFlusherTest "a confirm_render! after the flush is too late"
  # case locks in the current behaviour.
  class SuppressionFlushMiddleware
    sig { params(app: T.untyped).void }
    def initialize(app)
      @app = T.let(app, T.untyped)
    end

    sig { params(env: T::Hash[String, T.untyped]).returns(T.untyped) }
    def call(env)
      SuppressionFlusher.flush_after(@app, env)
    end
  end
end
