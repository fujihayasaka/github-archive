# typed: true
# frozen_string_literal: true

module BotHelper
  include ActionView::Helpers::TagHelper

  def bot_identifier(actor)
    if actor.is_a?(Bot) || actor.is_a?(PlatformTypes::Bot)
      bot_identifier_tag
    elsif actor.is_a?(Mannequin) || actor.is_a?(PlatformTypes::Mannequin)
      mannequin_identifier_tag
    end
  end

  def bot_identifier_tag
    content_tag(:span, "bot", class: "Label Label--secondary")
  end

  def mannequin_identifier_tag
    content_tag(:span, "mannequin", class: "Label Label--secondary")
  end
end
