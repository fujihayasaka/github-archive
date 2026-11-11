# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  # Downcases all name/id/aria attributes.
  class DowncaseNameFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("[name], [id], [aria-labelledby], [aria-describedby]")

    def selector
      SELECTOR
    end

    def call(node)
      if node["name"]
        node["name"] = node["name"].downcase
      end

      if node["id"]
        node["id"] = node["id"].downcase
      end

      if node["aria-describedby"]
        node["aria-describedby"] = node["aria-describedby"].downcase
      end

      if node["aria-labelledby"]
        node["aria-labelledby"] = node["aria-labelledby"].downcase
      end

      node
    end
  end
end
