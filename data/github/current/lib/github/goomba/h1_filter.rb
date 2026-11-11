# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Converts H1 headings to H2. Useful on pages where we want to limit user content from rendering H1's
  class H1Filter < NodeFilter
    SELECTOR = Goomba::Selector.new("h1")

    def selector
      SELECTOR
    end

    def call(node)
      ActionController::Base.helpers.content_tag(:h2, node.inner_html)
    end
  end
end
