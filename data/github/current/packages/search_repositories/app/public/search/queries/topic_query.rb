# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Search
  module Queries
    # The TopicQuery is used to search repository topics.
    class TopicQuery < ::Search::Query
      # The set of fields that can be queried when performing a topic search
      def self.field_list
        [:name, :created, :is, :repositories].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [:sort].freeze
      end

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      IS_VALUES = {
        featured: %w[featured not-featured],
        curated: %w[curated not-curated],
      }.freeze

      DEFAULT_SORT = %w[count desc].freeze

      DEFAULT_FILTER_KEYS = [:repository_count]

      # Construct a new TopicQuery instance that will highlight search results by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Topics.new
        @featured = opts.fetch(:featured, nil)
        @curated = opts.fetch(:curated, nil)
      end

      # Internal: Returns the Array of advanced search qualifiers supported by this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "topic" }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        @query_fields ||= ["name^1.5", "name.ngram^0.8", "display_name^1.2",
                           "short_description^0.8", "description^0.5", "aliases"]
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        {
          function_score: {
            query: {
              query_string: {
                query: escaped_query,
                fields: query_fields,
                phrase_slop: 10,
                default_operator: "AND",
                analyzer: "texty_search",
              },
            },
            score_mode: "multiply",
            functions: [
              {
                field_value_factor: {
                  field: "repository_count",
                  factor: 1.4,
                  modifier: "sqrt",
                  missing: 1,
                },
              },
            ],
          },
        }
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      # Internal: Build the filters required for the query.
      # Make sure when adding any default filter keys, to include them in DEFAULT_FILTER_KEYS
      # to ensure that empty queries aren't being sent to ES
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        filters[:name] = builder.query_filter(:"name.ngram")
        filters[:created_at] = builder.date_range_filter(:created_at, :created)

        unless @featured.nil?
          qualifiers[:featured].clear.must(@featured)
        end

        unless @curated.nil?
          qualifiers[:curated].clear.must(@curated)
        end

        if qualifiers.key?(:is)
          case qualifiers[:is].must.try(:first)
          when "featured"
            qualifiers[:featured].clear.must(true)
          when "curated"
            qualifiers[:curated].clear.must(true)
          when "not-featured"
            qualifiers[:featured].clear.must(false)
          when "not-curated"
            qualifiers[:curated].clear.must(false)
          end
        end

        # Exclude any topics that have no public repositories. Including these results would leak the existance of
        # *private* repositories that have those topics applied, because topics are deleted when the last associated
        # repository is deleted.
        qualifiers[:repositories].must_not("<=0")

        filters[:featured] = builder.term_filter(:featured)
        filters[:curated] = builder.term_filter(:curated)
        filters[:repository_count] = builder.range_filter(:repository_count, :repositories)
        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def valid_query?
        return false unless super

        if escaped_query.empty?
          filters = filter_hash.keys - DEFAULT_FILTER_KEYS
          if filters.empty?
            @invalid_reason = ::Search::Query::REASON_EMPTY_QUERY
            return false
          end
        end

        true
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str.start_with?("name") }
          # force the whole name to be included in the fragment
          fields[:"name.ngram"] = { number_of_fragments: 0 }
        end

        fields[:display_name] = { number_of_fragments: 0 }
        fields[:short_description] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        fields[:description] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        fields[:related] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        fields[:aliases] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }

        unless fields.empty?
          { encoder: :html, fields: fields, type: "plain" }
        end
      end

      # Internal: Prune results and then run the `normalizer` on the results if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of topic results and remove those for which the topic no longer
      # exists or is flagged.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        topic_ids = results.map { |h| h["_id"] }
        topics = Topic.where(id: topic_ids).index_by(&:id)

        results.delete_if do |result|
          doc_id = result["_id"].to_i
          prune_topic(result, topics[doc_id])
        end
      end

      def prune_topic(doc, topic)
        if topic.nil? || topic.flagged?
          RemoveFromSearchIndexJob.perform_later("topic", doc["_id"])
          true
        else
          doc["_model"] = topic
          !security_validation doc
        end
      end

      # Internal: Validate that the user is allowed to see the given search result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        topic = doc["_model"]
        return true unless topic.flagged? # non-flagged topics are public

        GitHub.dogstats.increment("search.query.errors.security",
                                  { tags: ["index:#{index.name}"] })
        false
      end
    end
  end
end
