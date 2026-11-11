# typed: true
# frozen_string_literal: true

class Integrations::AuthorizationView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels
  attr_reader :authorization
  attr_reader :application

  def application_safe_key
    application.key.sub(".", "-")
  end

  def logo_background_color_style_rule
    "background-color:##{application.preferred_bgcolor}"
  end
end
