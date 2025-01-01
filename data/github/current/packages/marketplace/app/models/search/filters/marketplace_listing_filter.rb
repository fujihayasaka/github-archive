# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # The MarketplaceListingFilter is critical for ensuring that users only see the
    # private Marketplace and Works with GitHub data that they are allowed to see. Any documents in
    # the search index that contain private data have two fields associated
    # with them: a `state` field and a `marketplace_id` field.
    #
    # Anyone is allowed to see documents where `state` is `verified`,
    # `verification_pending_from_unverified`, or `unverified` for Marketplace::Listings. For
    # everything else, the user needs to have permission to see the document.
    # This is determined by performing database queries and then returning a
    # list of private Marketplace and Works with GitHub listing IDs the user is allowed to see.
    # This list is used as a terms filter against the `marketplace_id` field.
    class MarketplaceListingFilter < ::Search::Filter
      attr_reader :current_user
      attr_reader :is_dsa_compliant

      # Create a new MarketplaceListingFilter.
      #
      # opts - The options Hash
      #   :current_user - the currently logged in User
      #
      def initialize(opts = {})
        super(opts)
        @field = :_id
        @current_user = options.fetch(:current_user, nil)
        @is_dsa_compliant = options.fetch(:is_dsa_compliant, false)
        bool_collection  # initialize our boolean collection
      end

      # Returns nil or a filter Hash.
      # returns actions or listings. All actions are returned. Listings that
      # are approved or are editable by the user are also returned.
      def must
        public_marketplace_listing_filter = [
          {
            bool: {
              must: [
                { term: { state: "verified" } },
                { term: { search_type: "marketplace_listing" } },
              ],
            },
          },
          {
            bool: {
              must: [
                { term: { state: "unverified" } },
                { term: { search_type: "marketplace_listing" } },
              ],
            },
          },
          {
            bool: {
              must: [
                { term: { state: "verification_pending_from_unverified" } },
                { term: { search_type: "marketplace_listing" } },
              ],
            },
          },
          {
            bool: {
              must: [
                { term: { state: "verified_creator" } },
                { term: { search_type: "marketplace_listing" } },
              ],
            },
          },
        ]

        must = {
          bool: {
            should: [
              {
                bool: {
                  must: [
                    { term: { state: "listed" } },
                    { term: { search_type: "azure_model" } },
                  ],
                },
              },
              {
                bool: {
                  must: [
                    { term: { state: "listed" } },
                    { term: { search_type: "repository_action" } },
                  ],
                },
              },
              {
                bool: {
                  should: [
                    {
                      bool: {
                        must: [
                          {
                            bool: {
                              should: public_marketplace_listing_filter,
                              minimum_should_match: 1,
                            },
                          },
                        ],
                      },
                    },
                  ],
              } },
            ],
          },
        }

        if is_dsa_compliant
          must[:bool][:should].last[:bool][:should].first[:bool][:must] << {
            bool: {
              must: [{ term: { is_dsa_compliant: true } }],
            },
          }
        end

        must[:bool][:should].last[:bool][:should] << build_term_filter(field, bool_collection.should) if bool_collection.should?

        must
      end

      # Returns nil or a filter Hash.
      def must_not
        build_term_filter(field, bool_collection.must_not)
      end

      # A `should` filter is not applicable.
      #
      # Returns nil
      def should; end

      # This filter will never be blank.
      #
      # Returns false
      def blank?
        false
      end

      # Override the superclass method and make it into a noop.
      #
      # Returns nil
      def build(values); end

      # For validating search results, this filter provides the set of all
      # accessible Marketplace::Listing that were allowed by the
      # search criteria. Results can be validated against this set of IDs.
      #
      # Returns an array containing the accessible IDs with a prefix to indicate whether it's a
      # Marketplace::Listing ID.
      def accessible_listing_ids
        return [] unless current_user

        marketplace_listing_ids = Marketplace::Listing.editable_by(current_user).pluck(:id)

        marketplace_listing_ids.map { |id| "mpl:#{id}" }
      end

      # Internal: Create the boolean collection that will be used by the
      # Marketplace::Listing filter. We include the current user's private
      # Marketplace::Listing IDs.
      #
      # Returns this filter's boolean collection.
      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new
        @bool_collection.should(accessible_listing_ids)
        @bool_collection
      end

      # Interal: Override the superclass method and make it a noop
      # implementation. Mapping the boolean collection is not applicable for
      # the Marketplace::Listing filter.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        bool_collection
      end
    end  # MarketplaceListingFilter
  end  # Filters
end  # Search
