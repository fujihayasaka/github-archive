# typed: true
# frozen_string_literal: true

module Search
  module Queries
    # The LabelQuery is used to search issue labels.
    class LabelQuery < ::Search::Query
      # The set of fields that can be queried when performing a label search
      def self.field_list
        [:sort].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [:sort].freeze
      end

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # The mapping of user-facing sort values to the corresponding values used in the search index.
      SORT_MAPPINGS = {
        "created" => "created_at",
        "updated" => "updated_at",
      }.freeze

      # Construct a new LabelQuery instance that will highlight search results by default.
      def initialize(opts = {}, &block)
        opts[:quote_words] = false
        super(opts, &block)
        @index = Elastomer::Indexes::Labels.new

        @repo_id = opts.fetch(:repo_id, nil)
        unless @repo_id
          raise "LabelQuery requires a repo_id so a specific repository's labels are searched"
        end
      end

      # Internal: Returns the Array of advanced search qualifiers supported by this query type.
      def qualifier_fields
        self.class.field_list
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        # The routing key is used to limit our search to the specific set of shards where the
        # labels are stored.
        { type: "label", routing: @repo_id }
      end

      # Internal: Returns the Array of field names that will be queried.
      # def query_fields
      #   return @query_fields if defined? @query_fields

      #   @query_fields = ["name^10", "name.ngram^2", "name.trigram^3", "description^1"]
      #   # @query_fields = ["name", "name.ngram", "name.trigram", "description"]
      #   @query_fields
      # end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if query.empty?

        should_array = [
          {
            # Returns documents that contain the words of a provided text in any order.
            match_phrase: {
              name: { query: query, boost: 10 },
            },
          },
          {
            # Returns documents that contain the words of a provided text, in the same order as provided. The last term of the provided text is treated as a prefix,
            match_phrase_prefix: {
              name: { query: query, boost: 8 },
            },
          },
          {
            # Returns documents that match a provided text, number, date or boolean value. The provided text is analyzed before matching.
            match: {
              name: { query: query, boost: 5, operator: "and" },
            },
          },
          {
            match: { "name.ngram" => { query: query, boost: 2 } },
          },
          {
            match: { "name.trigram" => { query: query, boost: 3 } },
          },
          {
            match: { description: { query: query, boost: 1 } },
          },
          {
            # You can use the term query to find documents based on a precise value
            # the text provided is not analyzed and is lowercased.
            term: {
              name: { value: query, boost: 15, case_insensitive: true },
            },
          }
        ]
        {
          bool: {
            should: should_array,
          },
        }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        ary = build_sort_section(sort, "_score", SORT_MAPPINGS)
        ary.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "created_at" == key || "updated_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end
        end

        ary
      end

      # Internal: Build the filters required for the query.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}
        filters[:name] = builder.query_filter(:"name.ngram")

        qualifiers[:repo_id].clear.must(@repo_id)
        filters[:repo_id] = builder.repository_filter(current_user, @repo_id, nil, user_session: user_session, ip: remote_ip)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {
          # force the whole name to be included in the fragment
          "name.ngram" => { number_of_fragments: 0 },
          :name => { number_of_fragments: 0 },

          :description => { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE },
        }

        { encoder: :html, require_field_match: true, fields: fields, type: "plain" }
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

      # Internal: Take the array of label results and remove those for which the label no longer
      # exists or is flagged. We will only perform this pruning in test and production; development
      # mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        label_ids = results.map { |h| h["_id"] }
        labels = Label.includes(:repository).where(id: label_ids).index_by(&:id)

        results.delete_if do |result|
          doc_id = result["_id"].to_i
          prune_label(result, labels[doc_id])
        end
      end

      def prune_label(doc, label)
        if label.nil?
          RemoveFromSearchIndexJob.perform_later("label", doc["_id"], doc["_routing"])
          true
        else
          doc["_model"] = label
          !security_validation doc
        end
      end

      # Internal: Validate that the user is allowed to see the given search result document.
      #
      # doc - The search result Hash
      #
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        label = doc["_model"]
        repo = label.repository
        return true if repo.public?

        @include_repos ||= filter_hash[:repo_id].accessible_repository_ids
        return true if @include_repos.include?(repo.id)

        GitHub.dogstats.increment("search.query.errors.security",
                                  { tags: ["index:" + index.name.to_s] })
        false
      end
    end
  end
end
