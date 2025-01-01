# typed: strict
# frozen_string_literal: true

module Elastomer::Indexes
  class MemexProjectItems < ::Elastomer::Index
    sig { override.returns(T::Hash[T.untyped, T.untyped]) }
    def self.mappings_hook
      mapping = Elastomer::Interfaces::Mapping::MemexProjectItem.create(field_specific_properties).to_hash
      { memex_project_item: mapping }
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def self.settings_hook
      settings = {
        analysis: {
          # Configuration for the process that transforms input from a text field into the representation optimized for search.
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis.html.
          #
          # You can test this configuration locally using the `_analyze` API:
          # https://www.elastic.co/guide/en/elasticsearch/reference/current/indices-analyze.html
          analyzer: {
            default: { type: "standard" },

            # Adds a custom analyzer that we can use selectively on certain fields.
            search_as_you_type: {
              # Specifies character transformations that happen before tokenization.
              char_filter: %w[special_character_filter],

              # A tokenizer receives the sequence of characters in from the input string and divides it into individual tokens.
              # This selects one of the built-in tokenizers ES provides as the one to use for our custom analyzer.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-whitespace-tokenizer.html
              tokenizer: "whitespace",

              # A token filter takes the list of tokens produced by the tokenizer and modifies them, either by applying
              # a transformation to a single token (e.g. lower-casing) adding/removing to the overall list (e.g. removing
              # stopwords like "and" or "the").
              #
              # This chooses a combination of both built-in token filters that ES provides and a few custom ones.
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-tokenfilters.html
              filter: %w[three_shingles case_changes flatten_graph lowercase asciifolding large_n_grams remove_duplicates]
            },

            # Adds a customer analyzer that is intended for use as the `search_analyzer` for the `search_as_you_type`
            # index analyzer above.
            #
            # See https://www.elastic.co/guide/en/elasticsearch/reference/current/specify-analyzer.html
            search_as_you_type_search_analyzer: {
              # Specifies character transformations that happen before tokenization to match the `search_as_you_type`
              # analyzer.
              char_filter: %w[special_character_filter],

              # This selects the built-in tokenizer that breaks the input string up into individual tokens.
              tokenizer: "whitespace",

              # This uses as wide a subset of the `search_as_you_type` token filters that we can without adding
              # new tokens to the input.
              filter: %w[lowercase asciifolding],
            },
          },

          # Configuration for character filters, which transform a stream of characters before they are passed to
          # a tokenizer.
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-charfilters.html.
          char_filter: {
            special_character_filter: {
              type: "mapping",
              mappings: [
                "` => ", # Removes backticks so that we can more easily match text inside code fences
                "\" => ", # Removes double quotes so that we can more easily match text inside double quotes
                "' => ", # Removes single quotes so that we can more easily match text inside single quotes
                "[ => ", # Removes square brackets so that we can more easily match text inside brackets
                "] => ", # Removes square brackets so that we can more easily match text inside brackets
                "( => ", # Removes parentheses so that we can more easily match text inside parentheses
                ") => ", # Removes parentheses so that we can more easily match text inside parentheses
              ]
            },
          },

          # Configures custom token filters for use in the `analyzer` config above.
          #
          # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-tokenfilters.html
          filter: {
            large_n_grams: {
              type: "edge_ngram",
              min_gram: 2,
              max_gram: 20,
              # The original token is preserved after analyzed by the edge_ngram filter and can be queried. For
              # example the token "getgroupingmetadata" will be analyzed into the tokens "ge", "get", "getg", "getgr",
              # etc. but the original token will still be stored in the index and can be queried.
              preserve_original: true
            },
            three_shingles: {
              type: "shingle",
              output_unigrams: true,
              max_shingle_size: 3,
            },
            case_changes: {
              # Elasticsearch recommends using the word_delimiter_graph filter instead of the word_delimiter filter
              # as the word_delimiter filter can produce invalid token graphs.
              #
              # See https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-word-delimiter-graph-tokenfilter.html#analysis-word-delimiter-graph-differences
              type: "word_delimiter_graph",
              catenate_words: false,
              catenate_numbers: false,
              generate_number_parts: false,
              generate_word_parts: true,
              catenate_all: false,
              split_on_case_change: true,
              preserve_original: true,
              split_on_numerics: false,
              stem_english_possessive: false
            },
          },
        },
        index: {
          number_of_shards:   GitHub.es_shard_count_for_memex_project_items,
          number_of_replicas: GitHub.es_number_of_replicas,
          auto_expand_replicas: GitHub.es_auto_expand_replicas,
          max_refresh_listeners: GitHub.es_max_refresh_listeners_for_memex_project_items,
          "queries.cache.enabled": true,
        }
      }

      ::Elastomer::Analyzers.configure_texty settings

      settings
    end

    # Constructs and returns Elastomer::Index instances for each index in that is
    # configured as writable in the `elastomer_index_memos` table.
    sig(:final) { override.returns(T::Array[T.attached_class]) }
    def self.writable_indices
      indices = super

      unless GitHub.enterprise? || FeatureFlag.vexi.enabled?(:memex_elasticsearch_dual_writes, default: false)
        indices.select!(&:primary?)
      end

      indices
    end

    sig { returns(T::Hash[Symbol, Elastomer::Interfaces::Mapping::FieldDataType]) }
    private_class_method def self.field_specific_properties
      result = T.let({}, T::Hash[Symbol, Elastomer::Interfaces::Mapping::FieldDataType])
      MemexProjectColumn::FieldDependency::FIELD_CLASS_REGISTRY
        .each_with_object(result) do |class_name, properties|
        klass = T.let(class_name.constantize, T.class_of(MemexProjectColumn::Field::Base))
        properties[klass.value_name] = klass.elasticsearch_mapping
      end
    end

    QueryParam   = T.type_alias { T.any(String, T::Hash[T.any(Symbol, String), T.untyped]) }
    # Perform a search request using the `query` document and the `params` hash.
    #
    # query   - The query Hash or JSON String
    # routing - A single routing String or an Array of routing Strings
    # params  - The request params as a SearchParams struct
    #          :type        - A single type String or an Array of type Strings
    #          :search_type - The type of search to perform
    #          :size        - The number of results to return
    #
    # See the ElasticSearch documentation
    # (https://www.elastic.co/guide/en/elasticsearch/reference/master/search-search.html#search-type)
    # for an explanation of the search type.
    #
    # Returns a Hash containing the search results.
    # Raises an ElastomerClient::Client::Error upon failure.
    #
    # Example Usage:
    #    index  = Elastomer::Indexes::MemexProjectItems.new
    #    # Preferred usage, with explicit routing key followed by parameters
    #    result = index.search(query, routing: 1, size: 10)
    #
    #    # Alternative valid usages
    #    result = index.search(query, routing: 1, **params)
    #    result = index.search(query, **params.merge(routing: 1))
    sig do
      override
        .params(query: QueryParam, routing: T.any(Integer, String), params: T.untyped)
        .returns(T::Hash[String, T.untyped])
    end
    def search(query, routing:, **params)
      safe_query do
        GitHub.tracer.in_span("elastomer query", attributes: {
          "db.elasticsearch.path_parts.index" => self.name,
          "db.elasticsearch.path_parts.routing" => routing,
          "db.elasticsearch.cluster.name" => self.cluster_name
        }, kind: :internal) do |_|
          docs.search(query, routing:, **params)
        end
      end
    end
    alias :query :search

    # Perform a search request using the `query` document and the `params` hash.
    #
    # query   - The query Hash or JSON String
    # params  - The request params Hash
    #          :type        - A single type String or an Array of type Strings
    #          :search_type - The type of search to perform
    #          :size        - The number of results to return
    #
    # See the ElasticSearch documentation
    # (https://www.elastic.co/guide/en/elasticsearch/reference/master/search-search.html#search-type)
    # for an explanation of the search type.
    #
    # Returns a Hash containing the search results.
    # Raises an ElastomerClient::Client::Error upon failure.
    sig { params(query: QueryParam, params: T::Hash[Symbol, T.untyped]).returns(T::Hash[String, T.untyped]) }
    def search_all(query, params: {})
      safe_query do
        GitHub.tracer.in_span("elastomer query", attributes: {
          "db.elasticsearch.path_parts.index" => self.name,
          "db.elasticsearch.cluster.name" => self.cluster_name
        }, kind: :internal) do |_|
          docs.search(query, params)
        end
      end
    end
    alias :query_all :search_all

    # Count the number of documents in the search index that match the given
    # query.
    #
    # query   - The query Hash or JSON String.
    # routing - A single routing String or an Array of routing Strings
    # type    - A single type String or an Array of type Strings
    #
    # Returns the number of matching documents.
    # Raises a ElastomerClient::Client::Error upon failure.
    sig do
      override.params(
        query: QueryParam,
        routing: T.any(Integer, String),
        type: T.nilable(T.any(String, T::Array[String]))
      ).returns(Integer)
    end
    def count(query, routing:, type: nil)
      safe_query do
        hash = docs.count(query, { routing:, type: }.compact)
        hash["count"].to_i
      end
    end
    alias :count_query :count

    # Count the number of documents in the search index that match the given
    # query.
    #
    # query   - The query Hash or JSON String.
    # type    - A single type String or an Array of type Strings
    #
    # Returns the number of matching documents.
    # Raises a ElastomerClient::Client::Error upon failure.
    sig { params(query: QueryParam, type: T.nilable(T.any(String, T::Array[String]))).returns(Integer) }
    def count_all(query, type: nil)
      safe_query do
        hash = docs.count(query, { type: }.compact)
        hash["count"].to_i
      end
    end
    alias :count_all_query :count_all

    # Updates the documents in the search index that match the given query.
    # Does not stop on conflicts.
    #
    # query   - The query Hash or JSON String.
    # params  - The request params Hash
    #
    # Returns a Hash containing the update results.
    sig do
      params(
        query: QueryParam,
        params: T.nilable(T::Hash[Symbol, T.untyped])
      ).returns(T::Hash[T.untyped, T.untyped])
    end
    def update_docs_by_query_ignoring_conflicts(query, params)
      query_parameters = params || {}
      docs.update_by_query(query, query_parameters.merge({ conflicts: "proceed" }))
    end

    sig { params(block: T.proc.void).returns(T.untyped) }
    private def safe_query(&block)
      begin
        yield
      rescue ::ElastomerClient::Client::Error => boom
        # NOTE: Failbot does not like large exception messages and will not forward them to failbot
        boom.message.slice!(1024..-1)
        raise boom
      end
    end
  end
end
