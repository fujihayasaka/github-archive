# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class WikiRelativeLinkFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "a")

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      !!context[:prefix_relative_links]
    end

    def call(node)
      href = node["href"]
      return unless href

      return if href.start_with?("wiki/")
      return if href.match(%r{^[a-z][a-z0-9\+\.\-]+:}i)  # RFC 3986 <3 U
      return if href.match(%r{^//?})
      return if href.match(/^#/)

      new_href = rewrite_relative_links(href.dup)
      node["href"] = new_href unless new_href == href
      node
    end

    def rewrite_relative_links(href)
      "wiki/#{href}"
    end
  end
end
