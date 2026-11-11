# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  #   Adds a noreferrer rel attribute to 'a' tags
  #
  #   Example: <a href="https://www.github.com">https://www.github.com</a>
  #   Becomes: <a href="https://www.github.com" rel="noreferrer">https://www.github.com</a>
  #
  class NoReferrerFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("a")

    def selector
      SELECTOR
    end

    def call(element)
      existing = (element["rel"] || "").split(/\s+/)
      element["rel"] = existing.concat(["noreferrer"]).uniq.join(" ")
      element
    end
  end
end
