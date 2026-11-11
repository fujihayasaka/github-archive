# typed: true
# frozen_string_literal: true

# These are GlobalInstrumenter subscriptions that emit Hydro events related to GitHub Copilot.
Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe(::Copilot::Events::COPILOT_LIMITER_BUST_CACHE) do |payload|
    message = {
      cache_type: payload[:cache_type],
      tracking_id: payload[:tracking_id],
      billable_customer_id: payload[:billable_customer_id],
    }

    publish(message, schema: "github.copilot.v3.CopilotLimiterBustCache")
  end
end
