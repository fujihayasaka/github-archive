# typed: true
# frozen_string_literal: true

module BotHelper
  include ActionView::Helpers::TagHelper
  include GitHub::ResilienceMixin

  def bot_identifier(actor)
    if actor.is_a?(Bot) || actor.is_a?(PlatformTypes::Bot)
      return ai_identifier_tag if actor_is_ai?(actor)
      bot_identifier_tag
    elsif actor.is_a?(Mannequin) || actor.is_a?(PlatformTypes::Mannequin)
      mannequin_identifier_tag
    end
  end

  def ai_identifier_tag
    content_tag(:span, "AI", class: "Label Label--secondary")
  end

  def bot_identifier_tag
    content_tag(:span, "Bot", class: "Label Label--secondary")
  end

  def mannequin_identifier_tag
    content_tag(:span, "mannequin", class: "Label Label--secondary")
  end

  private

  sig { params(actor: T.any(Bot, PlatformTypes::Bot)).returns(T::Boolean) }
  def actor_is_ai?(actor)
    @_actor_is_ai_cache ||= {}
    cache_key = actor.id
    return @_actor_is_ai_cache[cache_key] if @_actor_is_ai_cache.key?(cache_key)

    @_actor_is_ai_cache[cache_key] = compute_actor_is_ai?(actor)
  end

  sig { params(actor: T.any(Bot, PlatformTypes::Bot)).returns(T::Boolean) }
  def compute_actor_is_ai?(actor)
    with_database_error_fallback(fallback: false) do
      app = actor.is_a?(Bot) ? actor.integration : actor.app
      Apps::Privileged.capable?(:display_ai_identifier, app: app) || AgenticApp.display_ai_identifier_for_app?(app)
    end
  end
end
