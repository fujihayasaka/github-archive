# typed: true
# frozen_string_literal: true

module Stafftools::CopilotPrSummaryFeedbackHelper
  def sentiment_color_class(sentiment)
    if sentiment == "positive"
      "color-fg-success"
    elsif sentiment == "negative"
      "color-fg-danger"
    else
      "color-fg-attention"
    end
  end

  def milliseconds_to_seconds(milliseconds)
    return "" unless milliseconds
    (milliseconds / 1000.0).round(3)
  end
end
