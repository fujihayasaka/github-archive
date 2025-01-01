# typed: true
# frozen_string_literal: true

module Search
  module Queries
    class UserLoginQuery < UserQuery

      # FIXME if / when Elasticsearch fixes their upstream bug
      # see https://github.com/elastic/elasticsearch/issues/28980
      MAX_CLAUSE_COUNT = 512

      # Construct a UserLoginQuery. The query can provide weighted results to a
      # a list of users by providing a :friends option.
      #
      # opts - The options Hash.
      #   :friends - The Array of Users that should have a higher weight in the query
      #   :org - An organization who's members should have a higher weight in the query.
      #          If org is supplied and it is enterprise managed then we will only return users in the scope of the org.business.
      #   :org_member_scope - If :org is supplied then users are filtered by org membership and scope
      #   :include_business_orgs - If :org and :org_members_scope is supplied, then users are filtered by business membership
      #
      def initialize(opts = {}, &block)
        super(opts, &block)
        @friends = opts.fetch(:friends, [])
        @org = opts[:org]
        @org_member_scope = opts[:org_member_scope]
        @include_business_orgs = opts[:include_business_orgs]
        @exclude_suspended = opts[:exclude_suspended].nil? ? false : opts[:exclude_suspended]
      end

      # Internal: Constructs the query_hash. This method gets short cicuited if
      # we are not excluding suspended users as we will just be using the
      # query_doc in that case
      #
      # Returns the query as a Hash.
      def build_query
        return super unless @exclude_suspended
        {
          bool: {
            must_not: {
              exists: {
                field: :suspended_at
              }
            },
            must: query_doc,
            filter: build_query_filter,
          }
        }
      end

      # Internal: Constructs the "query" portion of the ES query document based
      # on the `query` attribute.
      #
      # Returns the query as a Hash.
      def query_doc
        return if escaped_query.empty?

        query_hash = {
          multi_match: {
            query:       query,
            fields:      %w[login^10 name login.ngram^0.8],
            operator:    "AND",
            type:        "most_fields",
            analyzer:    "lowercase",
          },
        }

        functions = []

        # If there are any friends provided for the actor, boost those results
        # if they match the query.
        if @friends.any?
          user_ids = @friends.collect(&:id).slice(0, MAX_CLAUSE_COUNT)
          functions << {
            filter: { terms: { user_id: user_ids } },
            weight: 10,
          }
        end

        # if org present we want to boost the scores of members
        # unless we're limiting to org members, no boost necessary
        if @org.present? && @org_member_scope.nil?
          org_filter_field = if @org.limit_to_public_members?(current_user)
            :public_org_ids
          else
            :all_org_ids
          end

          functions << {
            filter: { term: { org_filter_field => @org.id } },
            weight: 10,
          }
        end

        if functions.present?
          query_hash = {
            function_score: {
              query:     query_hash,
              functions: functions,
            },
          }
        end

        query_hash
      end

      def filter_hash
        return @filter_hash if defined? @filter_hash
        super

        if @org && @org_member_scope.present?
          attr = @org_member_scope == :all ? :all_org_ids : :public_org_ids

          if @include_business_orgs && (!GitHub.single_business_environment? && @org.business.present?)
            qualifiers[attr].must @org.business.organization_ids
          else
            qualifiers[attr].must @org.id
          end

          @filter_hash[attr] = builder.term_filter(attr)
        end

        @filter_hash
      end

      def build_highlight
        nil
      end

      def build_sort
        nil
      end

      def build_filter
        nil
      end

      def build_aggregations
        nil
      end

      # Returns the id of the enterprise managed business for @org, @business, or current_user
      def enterprise_id
        if @org&.enterprise_managed_user_enabled?
          @org&.business.id
        else
          super
        end
      end
    end  # UserLoginQuery
  end  # Queries
end  # Search
