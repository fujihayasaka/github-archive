# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class UserErrorFilter < OutputFilter
    def call(html)
      user_error = result[:user_error]
      return html unless user_error

      error_div = ActionController::Base.helpers.content_tag(:div, user_error, class: %w[flash flash-error mb-3])
      EscapeHelper.safe_join([error_div, EscapeHelper.raw(html)])
    end
  end
end
