# typed: strict
# frozen_string_literal: true

module Site::Contentful::Marketing::Core::Pages
  class IndexPage
    class WithGraphQlCards < IndexPage
      sig { override.returns(Site::Contentful::Page::CacheKey) }
      def cache_key
        Site::Contentful::Page::CacheKey.new(
          base: "site.swp.index",
          locale: @locale,
          path: @path,
          version: 4,
          user_provided_parameters: {
            order: order.to_s,
            **@query.transform_keys(&:to_sym).transform_values { |value| Array(value).join(",") },
          }
        )
      end

      # Fetch cards via GraphQL with the template_id. The template_id is required to allow fetching the cards before
      # the view data is fully processed/saved.
      sig do
        params(
          template_id: String,
          card_filters: T.nilable(Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter)
        ).returns({ total: Integer, items: T::Array[CardType] })
      end
      def graphql_cards(template_id, card_filters: nil)
        template = Site::Contentful::Marketing::GraphQL::TemplateIndex.new(id: template_id, locale: @locale)

        template.cards(limit:, skip:, order:, filters: card_filters)
      rescue StandardError => e
        Failbot.report(e, "Error fetching cards via GraphQL for IndexPage with template ID #{template_id}")
        { total: 0, items: [] }
      end

      sig { returns(Integer) }
      def total_pages
        # Get total cards from template fields, deleting the value
        total_cards = template.dig("fields", "totalCards")
        (total_cards.to_f / @per_page).ceil
      end

      # Keeping the interface the same, but just returning the view data since the cards are already filtered, sorted,
      # and paginated via GraphQL.
      sig { returns(T::Hash[String, T.untyped]) }
      def refined_view_data
        view_data
      end

      # Override to inject cards into the template entry within the raw data so they are cached with the rest of the
      # page data.
      sig { override.returns(JsonLikeType) }
      def fetch_data_from_contentful
        contentful_data = super

        template_entry = contentful_data.dig("includes", "Entry")&.find do |entry|
          entry.dig("sys", "contentType", "sys", "id") == "templateIndex"
        end

        if template_entry
          template_id = template_entry.dig("sys", "id")
          index_filters = template_entry.dig("fields", "filters").map do |filter_link|
            contentful_data.dig("includes", "Entry")&.find do |entry|
              entry.dig("sys", "id") == filter_link.dig("sys", "id")
            end
          end

          cards = graphql_cards(template_id, card_filters: card_filters(index_filters || []))

          template_entry["fields"]["cards"] = cards[:items]
          # Capturing the total cards here so it can be used for total_pages without needing another GraphQL call
          template_entry["fields"]["totalCards"] = cards[:total]
        end

        contentful_data
      end

      private

      # Returns a TemplateIndex::IndexCardFilter struct suitable for passing to the GraphQL API based on the current
      # query parameters. The TemplateIndex::IndexCardFilter is serialized to a Hash in the expected shape for the
      # GraphQL API.
      #
      # Example:
      #   Given the query params: { "topic" => ["ruby", "rails"], "level" => "beginner", "q" => "github copilot" }
      #   And index filters with groupValues of "topic" and "level"
      #   The resulting serialized filter will be:
      #     {
      #.      AND: [
      #         { indexFilters: { groupValue: "topic", filterValue_in: ["ruby", "rails"] } },
      #         { indexFilters: { groupValue: "level", filterValue_in: ["beginner"] } }
      #       ]
      #.      OR: [
      #         { card: { title_contains: "github copilot" } },
      #         { card: { description_contains: "github copilot" } }
      #       ]
      #     }
      #
      # AND and OR are only included if there are relevant filters or a search query present.
      #
      sig { params(index_filters: T::Array[JsonLikeType]).returns(T.nilable(Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter)) }
      def card_filters(index_filters)
        sanitized_filters = sanitized_index_filters(index_filters)

        filter_props = { AND: sanitized_filters, OR: search_filters }.compact
        return if filter_props.empty?

        Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter.new(**filter_props)
      end

      # Sanitizes the query parameters to only include those that match the provided index filters (from the
      # Template). These query parameters are then transformed into TemplateIndex::IndexCardFilters which can be
      # serialized into the shape expected by the GraphQL API.
      #
      # Example:
      #   Given the query params: { "topic" => ["ruby", "rails"], "level" => "beginner", "unrelated" => "value" }
      #   And index filters with groupValues of "topic" and "level"
      #   The resulting serialized filter will be:
      #     [
      #       { indexFilters: { groupValue: "topic", filterValue_in: ["ruby", "rails"] } },
      #       { indexFilters: { groupValue: "level", filterValue_in: ["beginner"] } }
      #     ]
      #
      # This will return nil if no valid filters are found.
      #
      sig do
        params(
          index_filters: T::Array[JsonLikeType]
        ).returns(
          T.nilable(
            T::Array[Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter]
          )
        )
      end
      def sanitized_index_filters(index_filters)
        sanitized = sanitize_query(index_filters)
        return if sanitized.empty?

        filter_queries = sanitized.map do |group, values|
          filter_values = Array(values).flat_map { |v| v.to_s.split(",") }

          Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter.with_index_filters(
            group_value: group.to_s,
            filter_values: filter_values
          )
        end
      end

      # Generates TemplateIndex::IndexCardFilters based on the "q" query parameter (if present), specifically
      # searching the card's title and description fields. These filteres can then be serialized into the shape
      # expected by the GraphQL API.
      #
      # Example:
      #   Given the query params: { "q" => "github copilot" }
      #   And index filters with groupValues of "topic" and "level"
      #   The resulting serialized filters will be:
      #     [
      #       { card: { title_contains: "github copilot" } },
      #       { card: { description_contains: "github copilot" } }
      #     ]
      #
      sig { returns(T.nilable(T::Array[Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter])) }
      def search_filters
        return unless @query[:q]

        filters = [
          Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter.with_card_search(title_contains: @query[:q]),
          Site::Contentful::Marketing::GraphQL::TemplateIndex::IndexCardFilter.with_card_search(description_contains: @query[:q])
        ].compact

        filters.empty? ? nil : filters
      end

      sig { params(index_filters: T::Array[JsonLikeType]).returns(T::Hash[Symbol, String]) }
      def sanitize_query(index_filters)
        @query.select do |key, _|
          index_filters.any? do |entry|
            key.to_s == entry.dig("fields", "groupValue")
          end
        end
      end

      sig { returns(Integer) }
      def limit
        @per_page
      end

      sig { returns(Integer) }
      def skip
        (@page_number - 1) * @per_page
      end

      sig { returns(Site::Contentful::Marketing::GraphQL::TemplateIndex::CardsCollectionOrder) }
      def order
        Site::Contentful::Marketing::GraphQL::TemplateIndex::CardsCollectionOrder.from(sort_param)
      end

      sig { returns(T.nilable(Symbol)) }
      def sort_param
        @query[:sort]&.to_sym
      end

      sig { override.returns(Integer) }
      def include
        3
      end
    end
  end
end
