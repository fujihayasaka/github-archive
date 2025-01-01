# typed: true
# frozen_string_literal: true

class Site::Contentful::CustomerStories::CardLinkComponent < ApplicationComponent
  include SvgHelper

  def initialize(heading:, body:, href:, icon:, analytics: nil, icon_theme: "default", card_count: 3)
    @heading = heading
    @body = body
    @href = href
    @icon = icon.to_sym
    @analytics = analytics
    @link_icon = is_external_url?(href) ? :"link-external" : :"chevron-right"
    @column_class = card_count_to_column_class.fetch(card_count, "col-lg-4")

    @icon_theme = case icon_theme
    when "red"
      "color-fg-severe color-bg-closed"
    when "pink"
      "color-fg-sponsors color-bg-sponsors"
    when "blue"
      "color-fg-accent color-bg-accent"
    else
      "color-fg-done color-bg-done"
    end
  end

  def card_count_to_column_class
    {
      4 => "col-lg-3",
      2 => "col-lg-6",
    }
  end

  def analytics
    analytics_tags_from_content(analytics: @analytics, text: @heading)
  end

  private def is_external_url?(url)
    true unless url.include?(GitHub.url)
  end
end
