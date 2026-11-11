# typed: true
# frozen_string_literal: true

# These are Hydro event subscriptions related to Automated Review Comments.

Hydro::EventForwarder.configure(source: GlobalInstrumenter) do
  subscribe("automated_review_comments.suggestion_feedback") do |payload|
    publish(
      payload,
      schema: "automated_review_comments.v0.SuggestionFeedback",
      topic: "automated_review_comments.v0.SuggestionFeedback",
      partition_key: payload[:repository_id],
    )
  end
end
