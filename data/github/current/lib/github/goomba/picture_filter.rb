# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Finds picture elements and wraps them in a themed-picture so that we can update
  # them client side based on the selected GitHub theme
  class PictureFilter < NodeFilter

    SELECTOR = Goomba::Selector.new("picture")

    def selector
      SELECTOR
    end

    def call(node)
      content = safe_html_if_sanitized(node.to_html.gsub("<br>\n", ""))
      picture = ActionController::Base.helpers.content_tag("themed-picture", content, { "data-catalyst-inline": true })
    end
  end
end
