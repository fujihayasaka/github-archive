# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  class HttpsFilter < NodeFilter
    attr_reader :selector

    def self.cache_key(context)
      "http_url=#{context[:http_url] || context[:base_url]}"
    end

    def initialize(*args)
      super

      @filter = GitHub::HTML::HttpsFilter.new("", context, result)
      @selector = Goomba::Selector.new("a[href^='#{@filter.http_url}']")
    end

    def call(node)
      node["href"] = node["href"].sub(/\Ahttp:/, "https:")
      node
    end
  end
end
