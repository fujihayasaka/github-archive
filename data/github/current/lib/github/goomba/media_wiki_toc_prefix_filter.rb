# typed: true
# frozen_string_literal: true

module GitHub::Goomba
  #   .mediawiki files generate their own table of contents, which we then break by prefixing
  #   all the `id` and `name` attributes with `user-content-`. This filter fixes up that
  #   auto-generated table of contents.
  #
  class MediaWikiTocPrefixFilter < NodeFilter
    SELECTOR = Goomba::Selector.new("table[summary='Contents'] a[href^='#']")

    def self.cache_key(context)
      context[:name_prefix]
    end

    def selector
      SELECTOR
    end

    def call(element)
      element["href"] = "#" + context[:name_prefix] + element["href"].delete_prefix("#")
      element
    end
  end
end
