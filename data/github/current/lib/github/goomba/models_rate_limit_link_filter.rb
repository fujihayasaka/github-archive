# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Enhances the Azure provided rate limit url with a user's tracking ID
  class ModelsRateLimitLinkFilter < NodeFilter
    include ActionView::Helpers::OutputSafetyHelper
    include OcticonsHelper

    SELECTOR = Goomba::Selector.new(match: "a[href^='#{GitHub.azure_ai_github_url}?modelName']")

    def selector
      SELECTOR
    end

    def call(element)
      element["href"] = context[:azure_link] if context[:azure_link]
      element
    end
  end
end
