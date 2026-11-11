# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Output filter that wraps the body in a `markdown-body class`
  class ModelsMarkdownBodyFilter < OutputFilter
    def call(html)
      "<div class='markdown-body'>#{html}</div>"
    end
  end
end
