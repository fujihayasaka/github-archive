# frozen_string_literal: true

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("browser.copilot_summarize_copy.click") do |payload|
    message = {
      analytics_tracking_id: payload[:analytics_tracking_id],
      repository_id: payload[:repository_id],
      organization_id: payload[:organization_id],
      content_type: payload[:content_type],
    }

    publish(message, schema: "github.copilot.v2.CopilotSummarizeCopyClick")
  end

  subscribe("browser.copilot_regenerate_summary.click") do |payload|
    message = {
      analytics_tracking_id: payload[:analytics_tracking_id],
      repository_id: payload[:repository_id],
      organization_id: payload[:organization_id],
      content_type: payload[:content_type],
    }

    publish(message, schema: "github.copilot.v2.CopilotRegenerateSummaryClick")
  end

  subscribe("browser.copilot_expand_summary_toggle.click") do |payload|
    message = {
      analytics_tracking_id: payload[:analytics_tracking_id],
      repository_id: payload[:repository_id],
      organization_id: payload[:organization_id],
      content_type: payload[:content_type],
      toggle_event: payload[:toggle_event]
    }

    publish(message, schema: "github.copilot.v2.CopilotExpandSummaryToggle")
  end
end
