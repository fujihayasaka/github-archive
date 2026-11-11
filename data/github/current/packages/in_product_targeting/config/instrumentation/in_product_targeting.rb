# typed: true
# frozen_string_literal: true

GlobalInstrumenter.subscribe("user.destroy") do |_name, _start, _ending, _transaction_id, payload|
  user = payload[:user]
  next unless user&.id

  InProductTargeting.domain.delete_matches_for_user(user_id: user.id)
end

# Suppression telemetry for the nudge priority coordination framework (ADR
# "Cross-Surface Nudge Priority Coordination" Step 7, github/in-product-messaging).
#
# InProductTargeting::PageNudgeCoordinator buffers one suppression per losing
# nudge; InProductTargeting::SuppressionFlusher (driven by
# InProductTargeting::SuppressionFlushMiddleware) emits these events at the end
# of the request:
#
# - in_product_targeting.nudge_suppressed — a nudge lost the priority contest
#   to a winner that confirmed render. `category` is the loser's existing
#   analytics category (so `suppressed` joins against `visible`/click events
#   with no taxonomy work) and `label` is
#   "lost_to:<winner_id>;tier:<loser_tier>;page:<page_key>;reason:<surface_cap|page_cap>".
# - in_product_targeting.nudge_suppression_orphaned — same shape with
#   "lost_to:none", emitted when no winner on the page confirmed render, so no
#   `suppressed` event lies about who won.
#
# Both forward to the generic github.analytics.v0.Event schema — the same
# schema nudge impression/click/dismiss analytics flow through — which has no
# `location` field; the page key is carried in the label's `page:` segment
# (the payload's `location` key is preserved for in-process subscribers).
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  [
    "in_product_targeting.nudge_suppressed",
    "in_product_targeting.nudge_suppression_orphaned",
  ].each do |event|
    subscribe(event) do |payload|
      message = {
        request_context: serializer.request_context(GitHub.context.to_hash),
        actor: serializer.user(payload[:actor]),
        category: payload[:category],
        action: payload[:action],
        label: payload[:label],
      }

      publish(message, schema: "github.analytics.v0.Event")
    end
  end
end
