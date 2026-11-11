# typed: true
# frozen_string_literal: true

module Search
  module Filters
    # Custom Elasticsearch filter that restricts search results for guest collaborators to only the organizations and
    # users they should see:
    #
    #   1. Themselves
    #   2. Organizations they are a member of
    #   3. Users who share at least one organization with them
    #
    # This filter is applied at the Elasticsearch query level, so that both the sidebar count and search results are
    # accurate.
    class GuestCollaboratorVisibilityFilter < ::Search::Filter
      include GitHub::Memoizer

      def initialize(current_user_id:, visible_org_ids:, **opts)
        @options = opts
        @current_user_id = current_user_id
        @visible_org_ids = visible_org_ids
        @valid = true
      end

      def build(values)
        return if values.blank?
        values
      end

      memoize def bool_collection
        bool_collection = ::Search::ParsedQuery::BoolCollection.new

        bool_collection.must = {
          bool: {
            should: [
              # The guest collaborator can always see themselves
              { term: { user_id: @current_user_id } },
              # Organizations the guest collaborator belongs to
              {
                bool: {
                  must: [
                    { term: { organization: true } },
                    { terms: { user_id: @visible_org_ids } },
                  ],
                },
              },
              # Users who share at least one organization with them
              {
                bool: {
                  must: [
                    { term: { organization: false } },
                    { terms: { all_org_ids: @visible_org_ids } },
                  ],
                },
              },
            ],
            minimum_should_match: 1,
          },
        }

        bool_collection
      end
    end
  end
end
