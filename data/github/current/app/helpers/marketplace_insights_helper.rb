# typed: false
# rubocop:disable Primer/PrimerOcticon
# frozen_string_literal: true

module MarketplaceInsightsHelper
  extend ActionView::Helpers::TagHelper

  def marketplace_insights_stat_change(current, previous, format = nil)
    return unless current && previous

    difference = (current - previous).to_i

    case format
    when :money
      value_text = "$#{number_with_delimiter(difference.abs)}"
    when :percent
      value_text = "#{number_with_delimiter(difference.abs)}%"
    else
      value_text = number_with_delimiter(difference.abs)
    end

    if difference >= 0
      icon_name = "arrow-up"
      text_color = "color-fg-success"
      tooltip = "Up #{value_text} since last period."
    else
      icon_name = "arrow-down"
      text_color = "color-fg-danger"
      tooltip = "Down #{value_text} since last period."
    end

    content_tag(:span, octicon(icon_name, class: "mr-2") + value_text, class: "tooltipped tooltipped-n #{text_color}", "aria-label": tooltip)
  end
end
