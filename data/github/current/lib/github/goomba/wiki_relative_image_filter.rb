# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class WikiRelativeImageFilter < NodeFilter
    SELECTOR = Goomba::Selector.new(match: "img")

    def selector
      SELECTOR
    end

    def self.enabled?(context)
      !!context[:prefix_relative_links]
    end

    def call(node)
      value = node["src"]
      return unless value

      return if value.start_with?("wiki/") # handles ![](wiki/images/image.png)
      return if value.match(/\/wiki\//) # handles ![](../repo-name/wiki/images/image.png)
      return if value.match(%r{^[a-z][a-z0-9\+\.\-]+:}i)  # RFC 3986 <3 U
      return if value.match(%r{^//?})
      return if value.match(/^#/)

      node["src"] = "wiki/#{value}"
      node
    end
  end
end
