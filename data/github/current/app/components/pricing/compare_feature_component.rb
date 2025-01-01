# typed: true
# frozen_string_literal: true

class Pricing::CompareFeatureComponent < ApplicationComponent
  attr_reader :title, :description, :free, :pro, :team, :enterprise, :footnote, :context

  ICON_COLOR = {
    check: :success,
    dash: :muted
  }

  def initialize(title:, description:, free:, team:, enterprise:, context:, footnote: nil, pro: nil, hide_enterprise: false, analytics: nil)
    @title = title
    @description = description
    @free = free
    @pro = pro
    @team = team
    @enterprise = enterprise
    @footnote = footnote
    @context = context
    @hide_enterprise = hide_enterprise
    @data = nil
    @analytics = analytics.present? ? analytics : {}
    @analytics[:category] = "Compare features"
  end

  private

  def before_render
    # Generate analytics data from content and merge with other data attributes
    short_title = @title.split(" ").first(6).join(" ")
    @analytics[:action] = "Click to expand"
    analytics = analytics_tags_from_content(analytics: @analytics, text: short_title)
    @analytics = analytics.present? ? analytics_click_attributes(**analytics) : nil
    @data = @analytics.present? && @data.present? ? @data.merge(@analytics) : @data || @analytics
  end

  def is_personal?
    @context == "personal"
  end

  def hide_enterprise?
    @hide_enterprise
  end

  def is_pro_plan?
    !@pro.nil?
  end

  def feature_support_text(text)
    if [:dash, :check].include?(text)
      render Primer::Beta::Octicon.new(text, size: :small, color: ICON_COLOR[text])
    else
      text
    end
  end

  def footnote_text(text)
    unless @footnote.blank? || %w[x check].include?(text)
      content_tag(:p, @footnote, class: "f6 color-fg-muted")
    end
  end
end
