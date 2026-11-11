# typed: strict
# frozen_string_literal: true

module InProductTargeting
  # Flushes buffered nudge-suppression telemetry at the end of each request
  # (ADR "Cross-Surface Nudge Priority Coordination" Step 7).
  #
  # PageNudgeCoordinator#decide buffers one suppression per losing nudge but
  # does not emit it, because at decide time we don't yet know which winners
  # actually rendered. SuppressionFlushMiddleware calls `flush_all!` once the
  # response is built (successful requests only — see the middleware for the
  # rationale); it iterates the request's coordinators once and lets each emit
  # its buffer — re-attributing losers to a confirmed-rendered winner or
  # orphaning them (see PageNudgeCoordinator#flush_suppression_events!).
  #
  # When the priority-coordinator flag is off (the default), `.for` never
  # stores a coordinator on the request, so the flush is a nil check and
  # nothing more.
  class SuppressionFlusher
    # The shared Rack body for the flush: call the inner app, then flush on a
    # normal return. Both SuppressionFlushMiddleware (which carries the unit
    # tests) and the boot-safe IpmSuppressionFlushAdapter (the instance
    # actually mounted in production) delegate here, so the two cannot drift and
    # the tested path is the production path.
    sig { params(app: T.untyped, env: T::Hash[String, T.untyped]).returns(T.untyped) }
    def self.flush_after(app, env)
      response = app.call(env)
      flush_all!
      response
    end

    # Flushes every coordinator created during the current request. Telemetry
    # must never break a response, so failures are reported, not raised.
    sig { void }
    def self.flush_all!
      coordinators = RequestStore.coordinators
      return if coordinators.nil? || coordinators.empty?

      coordinators.each_value do |coordinator|
        coordinator.flush_suppression_events!
      rescue => e
        Failbot.report(e)
      end
    end
  end
end
