# typed: true
# frozen_string_literal: true

module ExploreFeed
  class PopularDeveloper
    FOLLOWER_COUNT = 10_000
    DEVELOPER_MAX = 25
    CACHE_TIME_FORMAT = "%Y-%m-%e"

    def self.all(remote_ip: nil, force_cache_miss: false)
      cache_key_time = DateTime.current.strftime(CACHE_TIME_FORMAT)
      cache_key = ["popular", "developers", "recommendations", cache_key_time].join(".")

      GitHub.cache.fetch(cache_key, force: force_cache_miss) do
        search_results = build_query(remote_ip: remote_ip).execute
        per_page = search_results.per_page

        search_results.results.map.with_index do |result, index|
          score = (per_page - index).to_f / per_page.to_f
          { "user_id" => result["_id"], "score" => score }
        end
      end
    end

    def self.build_query(remote_ip:)
      ::Search::Queries::UserQuery.new(
        phrase: "followers:>#{FOLLOWER_COUNT}",
        per_page: DEVELOPER_MAX,
        remote_ip: remote_ip,
      )
    end
  end
end
