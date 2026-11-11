# typed: true
# frozen_string_literal: true

module Platform
  module Helpers
    class BlogBroadcast
      # The JSON feed for broadcasts on the GitHub Pages-based blog.
      def self.json_feed
        GitHub::JSON::CachedFetchRemoteUrl.fetch(
          url: "#{GitHub.blog_url}/broadcasts.json",
          cache_key: "blog:broadcasts:latest",
          default_value: [],
          hash_subkey: "items",
        )
      end
    end
  end
end
