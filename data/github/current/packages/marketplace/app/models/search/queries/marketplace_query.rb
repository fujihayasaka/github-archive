# typed: false
# frozen_string_literal: true

module Search
  module Queries
    # The MarketplaceQuery is used to search Marketplace and Works with GitHub listings.
    class MarketplaceQuery < ::Search::Query
      # The set of fields that can be queried when performing a Marketplace search
      def self.field_list
        [:is, :category, :name, :updated, :sort, :state, :"owner_login.raw", :model_family, :task].freeze
      end

      # A set of terms that have mutually exclusive values.
      def self.unique_field_list
        [:sort, :is]
      end

      # The default max offset is 1000
      # Global marketplace listing searches can exceed this
      # Only perform a search at this depth if the user requests it
      GLOBAL_MAX_OFFSET = 30_000

      VERIFIED_BOOST = 3.0
      UNVERIFIED_BOOST = 1.0
      PARTNER_BOOST = 2.5
      RECOMMENDED_BOOST = 3.5
      FEATURED_ACTION_BOOST = 3.5
      MODEL_BOOST = 100.0

      POPULARITY_SORT = "popularity"

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.

      SORT_MAPPINGS = {
        "created" => "created_at",
        "updated" => "updated_at",
        "_score" => "_score",
        POPULARITY_SORT => POPULARITY_SORT,
        "last-month-popularity" => "last_month_popularity"
      }.freeze

      SORT_MAPPINGS_WITH_DEPENDENTS = {
        "created" => "created_at",
        "updated" => "updated_at",
        "_score" => "_score",
        POPULARITY_SORT => POPULARITY_SORT,
        "last-month-popularity" => "last_month_popularity",
        "dependents-count" => "dependents_count"
      }.freeze

      # The mapping of user-facing keywords to the corresponding values used
      # in the search index.
      KEYWORD_MAPPINGS = {
        "publisher:" => "owner_login.raw:"
      }.freeze

      SEARCH_TYPES = {
        "MARKETPLACE" => "marketplace",
        "MARKETPLACE_COPILOT" => "marketplace",
        "MARKETPLACE_ACTIONS" => "repository-action",
        "MARKETPLACE_STACKS" => "repository-stack",
        "MARKETPLACE_TOOLS" => "marketplace-tools",
        "AZURE_MODELS" => "azure-models"
      }.freeze

      DEFAULT_SORT = %w[_score desc].freeze

      # The maximum number of characters returned in the highlighted fragments.
      FRAGMENT_SIZE = 200

      # Construct a new MarketplaceListingQuery instance that will highlight search results
      # by default.
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::MarketplaceListings.searcher
        # zero day bug fix here, check file app/platform/objects/query.rb passed param is verification_state and not state
        @state = opts.fetch(:verification_state, nil)
        @type = opts.fetch(:type, nil)
        @enterprise_compatible = opts.fetch(:enterprise_compatible, nil)
        @offers_free_trial = opts.fetch(:offers_free_trial, nil)
        @copilot_app = opts.fetch(:copilot_app, nil)


        # Exceeding the default max offset is rare, so only set this at a higher value
        # if requested by the user
        if (opts.fetch(:page, 0).to_i * opts.fetch(:per_page, 0).to_i > 1000) && opts[:current_user]&.feature_enabled?(:react_marketplace_deep_pagination)
          GitHub.dogstats.increment("gh.marketplace.deep_pagination", tags: ["type:#{@type}"])
          @max_offset = GLOBAL_MAX_OFFSET
        end
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      def search_type_filter
        types = @type

        if types.nil? && qualifiers.key?(:type)
          types = qualifiers[:type].must.nil? ? nil : qualifiers[:type].must.first
          qualifiers[:type].clear
        end

        search_types =
            case types
            when /marketplace-tools/i
              %w[marketplace_listing repository_action azure_model]
            when /repository-action/i
              %w[repository_action]
            when /repository-stack/i
              %w[repository_stack]
            when /azure-models/i
              %w[azure_model]
            else
              %w[marketplace_listing]
            end

        { terms: { search_type: search_types } }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        @query_fields ||= ["name^1.5", "name.ngram", "owner_login^1.1", "owner_name^1.1", "description", "short_description", "full_description", "categories", "model_family", "task"]
      end

      # Internal: build a query doc with a boosting portion to score verified => unverified => unlisted
      def build_query
        qd = query_doc
        bd = boost_doc
        filter = build_query_filter

        query = { should: bd }
        query[:must] = qd if qd
        query[:filter] = [search_type_filter]
        query[:filter] << filter if filter

        # scoring function place holder. We will explore in future if we need any scoring function.
        scoring_function = []

        {
          function_score: {
            query: {
              bool: query
            },
            functions: scoring_function,
            boost_mode: "sum"
          }
        }
      end

      def build_query_filter
        filter = ::Search::Filters::BoolFilter.new(filter_hash, aggregations)
        query_filter = filter.build

        if query_filter[:bool][:should]
          query_filter[:bool][:minimum_should_match] = 1
        end

        query_filter
      end

      # Internal: a query portion for boosting marketplace listings so they score higher and
      #           are shown first in search results. Verified listings should appear first,
      #           followed by unverified listings (including those pending verification),
      #           followed by other documents in the 'marketplace-search' alias (eg. actions).
      def boost_doc
        [
          *marketplace_listing_boost,
          *repository_action_boost,
          *model_boost,
        ]
      end

      def marketplace_listing_boost
        # recommendation boost filter for recommended apps.
        recommendation_filter = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { is_recommended: true } },
                  { term: { search_type: "marketplace_listing" } },
                ]
              }
            },
            boost: RECOMMENDED_BOOST,
          },
        }

        # verified filter boost for verified apps
        verified_filter = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { state: "verified" } },
                  { term: { search_type: "marketplace_listing" } },
                ]
              }
            },
            boost: VERIFIED_BOOST,
          },
        }

        # verified owner filter boost for verified owner apps
        verified_owner_filter = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { is_verified_owner: true } },
                  { term: { search_type: "marketplace_listing" } },
                ]
              }
            },
            boost: VERIFIED_BOOST,
          },
        }

        # unverified filter boost for unverified from unverified apps
        unverified_filter = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { terms: { state: %w[unverified verification_pending_from_unverified] } },
                  { term: { search_type: "marketplace_listing" } },
                ]
              }
            },
            boost: UNVERIFIED_BOOST,
          },
        }

        # returns the composed filter
        [
          verified_filter,
          verified_owner_filter,
          unverified_filter,
          recommendation_filter
        ]
      end

      def repository_action_boost
        verified_repo_action = [
          { term: { search_type: "repository_action" } },
          { term: { is_verified_owner: true } },
        ]

        featured_action_filter = {
          constant_score: {
            filter: {
              bool: {
                must: [
                  { term: { featured: true } },
                  { term: { search_type: "repository_action" } },
                ]
              }
            },
            boost: FEATURED_ACTION_BOOST,
          },
        }

        boost = [
          {
            constant_score: {
              filter: {
                bool: {
                  must: [
                    { term: { search_type: "repository_action" } },
                    { term: { is_verified_owner: false } },
                  ]
                }
              },
              boost: UNVERIFIED_BOOST,
            },
          }
        ]

        # When there is a query, we dont need to change queries at all as the search will change the results anyways
        # and there's no risk of "favouring" anyone by mistake.
        # Also, maybe we _do_ want to search "Azure" or something.
        if escaped_query.present? || qualifiers.key?(:owner_login)
          boost << {
            constant_score: {
              filter: {
                bool: {
                  must: verified_repo_action
                }
              },
              boost: VERIFIED_BOOST,
            },
          }
        else
          # When the search query is blank, we don't want to boost GitHub and Microsoft entries as much.
          # These actions were showing up on the front page and dominating the top results.
          # We want to avoid the situation where it appears that we are favouring ourselves or our parent company,
          # which could be poorly received by the community
          boost += [
            {
              constant_score: {
                filter: {
                  bool: {
                    must: verified_repo_action,
                    must_not: [
                      { terms: { "owner_login.raw": ::RepositoryAction::GITHUB_MICROSOFT_CREATORS } },
                    ]
                  }
                },
                boost: VERIFIED_BOOST,
              },
            },
            {
              constant_score: {
                filter: {
                  bool: {
                    must: verified_repo_action + [{ terms: { "owner_login.raw": ::RepositoryAction::GITHUB_MICROSOFT_CREATORS } }]
                  }
                },
                boost: PARTNER_BOOST, # We still want to boost these partners, but not as much
              },
            },
            featured_action_filter,
          ]
        end

        boost
      end

      def model_boost
        [
          {
            constant_score: {
              filter: {
                bool: {
                  must: [
                    { term: { search_type: "azure_model" } },
                  ]
                }
              },
              boost: MODEL_BOOST,
            },
          }
        ]
      end

      # Internal: Constructs the search query based on the `query` attribute.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        {
          query_string: {
            query: escaped_query,
            fields: query_fields,
            phrase_slop: 10,
            default_operator: "AND",
            analyzer: "texty_search",
          },
        }
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        if GitHub.flipper[:dependents_count_marketplace].enabled?(current_user)
          sort_mappings = SORT_MAPPINGS_WITH_DEPENDENTS
        else
          sort_mappings = SORT_MAPPINGS
        end

        ary = build_sort_section(sort, sort_mappings)
        ary&.each do |item|
          next unless item.is_a?(Hash)

          key = item.keys.first
          if "created_at" == key || "updated_at" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "date" }
          end

          if "dependents_count" == key
            order = item[key]
            item[key] = { "order" => order, "unmapped_type" => "integer" }
          end

          # "Popularity" is measured differently for different entity types, hence, we are replacing the
          # "sort by popularity" with what it means for each entity type. For example, for apps it is
          # measured by the installation_count and for actions by the stars count.
          # Since popularity is tightly coupled with the entity, we can only sort by popularity when the
          # "type" is provided. In case the type is not provided and sort by popularity is requested,
          # we internally default to sort by [_score desc].
          if key == POPULARITY_SORT
            if @type == "marketplace"
              item["installation_count"] = item.delete POPULARITY_SORT
            elsif @type == "repository-action" || @type == "repository-stack"
              item["stars"] = item.delete POPULARITY_SORT
            else
              item["_score"] = item.delete POPULARITY_SORT
            end
          end

          if key == "last_month_popularity"
            item.delete("last_month_popularity")
            if @type == "marketplace"
              item["installation_count_last_month"] = "desc"
            end
          end
        end
        ary
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      ### Move to Helper
      def state_map(state)
        result = nil
        if %w[verified draft rejected archived].include? state
          result = state
        elsif state == "verification-pending-from-draft"
          result = "verification_pending_from_draft"
        end
      end

      # Internal: Build the filters required for the query.
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        filters = {}

        filters[:name] = builder.query_filter(:"name.ngram")
        filters[:created_at] = builder.date_range_filter(:created_at, :created)
        filters[:updated_at] = builder.date_range_filter(:updated_at, :updated)
        filters[:owner_login] = builder.term_filter(:"owner_login.raw") { |owner_login| owner_login.downcase }
        filters[:marketplace_id] = builder.marketplace_listing_filter(current_user)

        if [true, false].include? @enterprise_compatible
          qualifiers[:enterprise_compatible].clear.must(@enterprise_compatible)
          filters[:enterprise_compatible] = builder.term_filter(:enterprise_compatible)
        end

        if [true, false].include? @offers_free_trial
          qualifiers[:offers_free_trial].clear.must(@offers_free_trial)
          filters[:offers_free_trial] = builder.term_filter(:offers_free_trial)
        end

        if [true, false].include?(@copilot_app) && @type == "marketplace"
          qualifiers[:copilot_app].clear.must(@copilot_app)
          filters[:copilot_app] = builder.term_filter(:copilot_app)
        end

        if qualifiers.key?(:is) && qualifiers[:is].must?
          res = state_map(qualifiers[:is].must.first)
          if res
            qualifiers[:state].clear.must(res)
          else
            qualifiers[:is].must.each do |value|
              qualifiers[:category].must(value.downcase)
            end
          end
          filters[:state] = builder.term_filter(:state)
        end

        # @state overrides state from "is:[state]" in query
        if @state.present?
          res = state_map(@state)
          if res
            qualifiers[:state].clear.must(res)
          else
            if @state == "verified_creator"
              if @type == "marketplace"
                qualifiers[:state].clear.should("verified")
              end
              qualifiers[:is_verified_owner].clear.must(true)
            end
          end
          filters[:state] = builder.term_filter(:state)
        else
          filters[:state] = builder.term_filter(:state, execution: :or)
        end

        filters[:is_verified_owner] = builder.term_filter(:is_verified_owner)

        filters[:categories] = builder.term_filter(
          :"categories.raw",
          :category,
          execution: :or,
          missing: :none) { |category| category.downcase }

        filters[:task] = builder.term_filter(:task)
        filters[:model_family] = builder.term_filter(:model_family)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str.start_with?("name") }
          # force the whole name to be included in the fragment
          fields[:"name.ngram"] = { number_of_fragments: 0 }
        end

        fields[:description] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        fields[:short_description] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }
        fields[:full_description] = { number_of_fragments: 1, fragment_size: FRAGMENT_SIZE }

        unless fields.empty?
          { encoder: :html, fields: fields, type: "plain" }
        end
      end

      # Internal: Prune results and then run the `normalizer` on the results
      # if one was provided.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the normalized Array of hits.
      def normalize(results)
        prune_results(results) unless @results_pruned
        super(results)
      end

      # Internal: Take the array of listing results and remove those for which
      # the listing no longer exists. We will only perform this pruning in test
      # and production; development mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        marketplace_listing_ids = []
        repository_action_ids = []
        azure_model_ids = []

        error_reported = false

        results.each do |result|
          doc_id = result["_id"].to_i

          case result["_source"]["search_type"]
          when "marketplace_listing"     then marketplace_listing_ids << doc_id
          when "repository_action"       then repository_action_ids << doc_id
          when "azure_model"             then azure_model_ids << doc_id
          else
            unless error_reported
              GitHub.dogstats.increment("search.query.errors.type",
                                        { tags: ["index:" + index.name.to_s] })
              error_reported = true
            end
          end
        end

        # Preload relations used in MarketplaceListingResultView:
        marketplace_listings = Marketplace::Listing.
          where(id: marketplace_listing_ids).index_by(&:id)

        repository_actions = RepositoryAction.
          includes(:repository).
          where(id: repository_action_ids).index_by(&:id)

        azure_models = AzureModels::CatalogItem.
          where(id: azure_model_ids).index_by(&:id)

        results.delete_if do |result|
          doc_id = result["_id"].to_i

          case result["_source"]["search_type"]
          when "marketplace_listing"
            prune_marketplace_listing(result, marketplace_listings[doc_id])
          when "repository_action"
            prune_repository_action(result, repository_actions[doc_id])
          when "azure_model"
            # Since azure models are updated in a regular job, we can prune them there instead of having
            # to do it real-time in the search query.
            result["_model"] = azure_models[doc_id]
            false
          end
        end
      end

      def prune_marketplace_listing(doc, listing)
        if listing.nil? || listing.can_remove_from_search_index?
          RemoveFromSearchIndexJob.perform_later("marketplace_listing", doc["_id"])
          true
        else
          doc["_model"] = listing
          !security_validation doc
        end
      end

      def prune_repository_action(doc, action)
        if action.nil? || action.can_remove_from_search_index?
          RemoveFromSearchIndexJob.perform_later("repository_action", doc["_id"])
          true
        else
          doc["_model"] = action
          !security_validation doc
        end
      end

      # Internal: Validate that the user is allowed to see the given search result document.
      #
      # doc - The search result Hash
      #
      # Returns nil
      # Returns a boolean indicating visibility.
      def security_validation(doc)
        tool = doc["_model"]
        return true if tool.can_viewer_see?(current_user)

        GitHub.dogstats.increment("search.query.errors.security",
                                  { tags: ["index:" + index.name.to_s] })
        false
      end
    end
  end
end
