# typed: true
# frozen_string_literal: true

require "set"

module TrustTiers
  class EngagedOssSearch
    def self.build_query(query_phrase, page)
      Search::Queries::RepoQuery.new(
        page: page,
        per_page: 100,
        phrase: query_phrase,
        sort: %w[stars desc],
      )
    end

    def self.search(query_phrase, search_top)
      GitHub.logger.info(
        "code.namespace" => self.class.name,
        "code.function" => __method__.to_s,
        "query_phrase" => query_phrase,
        "search_top" => search_top
      )

      page = 1
      index = 0

      repos = []

      while index < search_top
        query = build_query(query_phrase, page)

        unless query.valid_query?
          raise Exception.new "Invalid search query: #{query.invalid_reason}"
        end

        results = query.execute
        count = results.results.length

        if count == 0
          break
        end

        results.results.each do |result|
          index += 1

          # serialize like the search API would; resolves node_id
          repo = Api::Serializer.serialize(:repository_hash, result["_model"])

          repos.push({
            nwo: repo[:full_name],
            database_id: repo[:id]
          })

          if index >= search_top
            break
          end
        end

        page += 1

        if count < 100
          break
        end
      end

      repos
    end
  end
end
