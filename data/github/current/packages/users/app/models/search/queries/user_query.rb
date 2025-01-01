# typed: true
# frozen_string_literal: true

module Search
  module Queries

    class UserQuery < ::Search::Query

      # The set of fields that can be queried when performing a user search
      def self.field_list
        [:in, :sort, :fullname, :repos, :location, :lang, :language, :user, :org, :created,
        :followers, :type, :is].freeze
      end

      # The mapping of user-facing sort values to the corresponding values used
      # in the search index.
      SORT_MAPPINGS = {
        "followers"    => "followers",
        "joined"       => "created_at",
        "repositories" => "repos",
      }.freeze

      IS_VALUES = {
        sponsorable: %w[sponsorable],
      }.freeze

      # The default sort ordering to use in the absence of a query or any
      # other sort information
      DEFAULT_SORT = %w[followers desc].freeze

      DEFAULT_FILTER_KEYS = [:emu]

      # Construct a UserQuery. The query can be restricted to a single
      # language by providing a :language option.
      #
      # opts - The options Hash.
      #   :language - The language name or Linguist::Language instance to filter by
      #   :business - The business instance when the query is being made in the context of a business.
      #               Currently only used in UserLoginQuery. If business is supplied and it is
      #               enterprise managed we will only return users in the same business.
      #
      def initialize(opts = {}, &block)
        super(opts, &block)
        @index = Elastomer::Indexes::Users.new
        @language = opts.fetch(:language, nil)
        @business = opts[:business]
      end

      # Internal: Returns the Array of advanced search qualifiers supported by
      # this query type.
      def qualifier_fields
        self.class.field_list
      end

      def qualifiers=(value)
        super(value)

        if qualifiers.key?(:is) && qualifiers[:is].must?
          qualifiers[:is].must.each do |value|
            case value.downcase
            when "sponsorable"
              qualifiers[:sponsorable].clear.must(true)
            end
          end
        end
      end

      # Internal: Returns the Array of fields that support aggregation queries.
      def aggregation_fields
        [:language_id]
      end

      # Internal: Returns a Hash that will be passed as URL params for the query.
      def query_params
        { type: "user" }
      end

      # Internal: Returns the Array of field names that will be queried.
      def query_fields
        return @query_fields if defined? @query_fields
        @query_fields = []

        search_in.each do |field|
          case field
          when "login"; @query_fields << "login^10" << "login.ngram^0.8"
          when "email"; @query_fields << "email" << "email.plain"
          when "name";  @query_fields << "name^1.2"
          end
        end

        @query_fields = %w[login^10 login.ngram^0.8 email email.plain name^1.2 profile_bio] if @query_fields.empty?
        @query_fields
      end

      # Internal: Constructs the actual `:query` portion of the query
      # document. This will later be wrapped in a filtered query if search
      # qualifiers were also used.
      #
      # Returns the search query Hash.
      def query_doc
        return if escaped_query.empty?

        query = { query_string: {
          query: escaped_query,
          fields: query_fields,
          default_operator: "AND",
          analyzer: "lowercase",
        } }

        query = { function_score: {
          query: query,
          score_mode: "multiply",
          functions: [{
            field_value_factor: {
              field: "rank",
              missing: 1,
            },
          }],
        } }

        query
      end

      # Internal: Returns the highlight Hash.
      def build_highlight
        fields = {}

        if query_fields.any? { |str| str =~ /^login/ }
          fields["login.ngram"] = { number_of_fragments: 0 }
          fields[:login]        = { number_of_fragments: 0 }
        end

        if query_fields.any? { |str| str =~ /^email/ }
          fields["email.plain"] = { number_of_fragments: 0 }
          fields[:email]        = { number_of_fragments: 0 }
        end

        if query_fields.any? { |str| str =~ /^name/ }
          fields[:name] = { number_of_fragments: 0 }
        end

        if query_fields.any? { |str| str =~ /^profile_bio/ }
          fields[:profile_bio] = { number_of_fragments: 0 }
        end

        unless fields.empty?
          { encoder: :html,
            require_field_match: true,
            fields: fields,
            type: "plain"
          }
        end
      end

      # Internal: Returns the sorting options Array.
      def build_sort
        return if sort.blank?

        build_sort_section(sort, "_score", SORT_MAPPINGS)
      end

      # Returns the default sort ordering to use in the absence of a query or
      # any other sort information.
      def default_sort
        DEFAULT_SORT
      end

      # Internal: We need to use the same filters for the query and for the
      # aggregations with the exception of the language query. Since we are aggregationing
      # on language, applying a language filter would be most unhelpful.
      # Make sure when adding any default filter keys, to include them in DEFAULT_FILTER_KEYS
      # to ensure that empty queries aren't being sent to ES
      #
      # Returns the Hash of filter hashes.
      def filter_hash
        return @filter_hash if defined? @filter_hash

        # override the language if created with a language option
        unless @language.nil?
          qualifiers[:lang].clear
          qualifiers[:language].clear
          qualifiers[:language].must @language
        end

        filters = {}

        filters[:sponsorable] = builder.term_filter(:sponsorable)
        filters[:language_id] = builder.language_filter(:language_id, :language_id, :language, :lang)
        filters[:location]   = builder.query_filter(:location) { |str| str.downcase }
        filters[:name]       = builder.query_filter(:name, :fullname) { |str| str.downcase }
        filters[:user] = builder.user_filter(
          :user_id,
          :user,
          :org,
          current_user: current_user,
          exclude_private_profiles: true,
          cap_filter: cap_filter
        )

        filters[:followers]  = builder.range_filter(:followers)
        filters[:repos]      = builder.range_filter(:repos)
        filters[:created_at] = builder.date_range_filter(:created_at, :created)

        filters[:type] = build_type_filter

        business_id = enterprise_id
        filters[:emu] = builder.enterprise_managed_user_filter(business_id)

        filters.delete_if { |_name, filter| filter.nil? || (filter.valid? && filter.blank?) }

        @filter_hash = filters
      end

      def build_type_filter
        return unless qualifiers.key? :type
        return unless qualifiers[:type].must?

        builder.term_filter(:organization, :type, singular: true) do |value|
          case value.downcase
          when "user"; false
          when "org", "organization"; true
          end
        end
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

      # Internal: Take the array of user results and remove those that
      # no longer exist in the database or have been flagged as spammy. We
      # will only perform this pruning in test and production; development
      # mode is for testing out everything.
      #
      # results - An Array of hits from the search index.
      #
      # Returns the pruned Array of hits.
      def prune_results(results)
        user_ids = results.map { |h| h["_id"] }
        users = if user_ids.any?
          User.includes(:profile).where(id: user_ids).index_by(&:id)
        else
          []
        end

        enterprise_managed_business_id = enterprise_id

        results.delete_if do |h|
          user_id = h["_id"].to_i
          user = users[user_id]

          if (user.nil? || user.spammy || user.mannequin?) && !Rails.env.development?
            RemoveFromSearchIndexJob.perform_later("user", user_id)
            true
          elsif prune_mismatch?(user, enterprise_managed_business_id)
            GitHub.logger.info("Unexpected pruning in user query due to enterprise id mismatch",
              "code.namespace" => "Search::Queries::UserQuery",
              "code.function" => "prune_results",
              "gh.business.exist" => (@business != nil),
              "gh.business.id" => @business&.id,
              "gh.business.is_enterprise_managed" => @business&.enterprise_managed_user_enabled?,
              "gh.current_user.exist" => (current_user != nil),
              "gh.current_user.id" => current_user&.id,
              "gh.current_user.is_enterprise_managed" => current_user&.is_enterprise_managed?,
              "gh.current_user.enterprise_id" => current_user&.enterprise_managed_business&.id,
              "gh.organization.exist" => (@org != nil),
              "gh.organization.id" => @org&.id,
              "gh.organization.is_enterprise_managed" => @org&.enterprise_managed_user_enabled?,
              "gh.organization.enterprise_id" => @org&.business&.id,
              "gh.user.search.enterprise_managed_business_id" => enterprise_managed_business_id,
              "gh.user.search.result_user.id" => user_id,
              "gh.user.search.result_user.is_enterprise_managed" => user&.is_enterprise_managed?,
              "gh.user.search.result_user.enterprise_id" => user&.enterprise_managed_business&.id,
              "gh.user.search.search_phrase" => phrase
            )

            true
          # Prune any users that were returned who are protected by conditional access policies
          elsif protected_account_ids.any? && protected_account_ids.include?(user_id)
            true
          else
            h["_model"] = user
            false
          end
        end
      end

      # Returns the id of the enterprise managed business for the current_user or @business
      # Returns nil if current_user or @businsses is not enterprise_managed or if they are nil
      def enterprise_id
        if current_user&.is_enterprise_managed? || @business&.enterprise_managed_user_enabled?
          current_user&.enterprise_managed_business&.id || @business&.id
        else
          nil
        end
      end

      # Returns false if the enterprise managed business for this user matches the current_user's business or @business
      # Returns true if the user does not belong to an enterprise managed business
      # Returns true if the user's enterprise managed business does not match the current_user's business or @business
      def prune_mismatch?(result_user, business_id)
        result_enterprise_id =
          case result_user
          when Organization
            result_user.enterprise_managed_user_enabled? ? result_user.business&.id : nil
          when User
            result_user.is_enterprise_managed? ? result_user.enterprise_managed_business&.id : nil
          else
            nil
          end

        business_id != result_enterprise_id
      end

      def cap_filter
        return @cap_filter if defined?(@cap_filter)

        @cap_filter = ConditionalAccess::Web::Filter.new(self)
      end

      def protected_account_ids
        return @protected_account_ids if defined?(@protected_account_ids)

        @protected_account_ids = cap_filter.unauthorized_resource_ids(
          current_user&.resources_for_cap_filter,
          only: :ip_allowlist
        )
      end
    end  # UserQuery
  end  # Queries
end  # Search
