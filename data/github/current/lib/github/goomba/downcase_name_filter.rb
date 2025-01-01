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
        node["name"] = node["name"].mb_chars.downcase.to_s
      end

      if node["id"]
        node["id"] = node["id"].mb_chars.downcase.to_s
      end

      if node["aria-describedby"]
        node["aria-describedby"] = node["aria-describedby"].mb_chars.downcase.to_s
      end

      if node["aria-labelledby"]
        node["aria-labelledby"] = node["aria-labelledby"].mb_chars.downcase.to_s
      end

      node
    end
  end
end
