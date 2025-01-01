# typed: false
# frozen_string_literal: true

module Search
  module Filters
    # The ProjectFilter ensures that users do not see ElasticSearch
    # documents associated with private org and user projects that they do not
    # have access to.
    #
    # Anyone is allowed to see documents where `public` is true. For everything
    # else, the user needs to have permission to see the document. This is
    # determined by performing database queries and then returning a list of
    # private project IDs the user is allowed to see. This list is used as a
    # terms filter against the `_id` field in the projects index.
    #
    # When the `scoped` flag is passed on a User/Organization search,
    # the search includes public/private repo projects within the User/Organization.
    # Othwerise when `scoped` is `false` (by default), the search only includes
    # User/Organization projects.
    class ProjectFilter < ::Search::Filter
      attr_reader :current_user, :owner_id, :scoped

      def initialize(owner_id:, current_user:, scoped: false, **opts)
        super(opts)

        @field ||= :_id
        @keys = nil

        @owner_id = owner_id
        @current_user = current_user
        @scoped = scoped

        bool_collection # initialize our boolean collection
      end

      # This reason can be used when the organization project filter is invalid.
      def invalid_reason
        "The listed users and projects cannot be searched either because the resources do not exist or you do not have permission to view them."
      end

      # Returns nil or a filter Hash.
      def must
        project_visibility_filters = [{ term: { public: true } }]

        if bool_collection.must?
          # Pass the list of private project IDs to include from bool_collection
          project_visibility_filters << build_term_filter(field, bool_collection.must)
        end

        if project_visibility_filters.size > 1
          # If we have multiple visibility filters, construct an OR query.
          {
            bool: {
              should: project_visibility_filters,
            },
          }
        elsif project_visibility_filters.size == 1
          # If we have a single visibility filter, we can just return that.
          project_visibility_filters.first
        else
          # If we have no visibility filters, return nothing.
          nil
        end
      end

      # A `should` filter is not applicable to the organization project filter.
      #
      # Returns nil.
      def should
      end

      # This will never be blank.
      #
      # Returns a boolean.
      def blank?
        false
      end

      # Override the superclass method and make it into a noop.
      #
      # Returns nil
      def build(values)
      end

      # For validating search results, this filter provides the set of all
      # accessible project IDs that were allowed by the search criteria.
      # Results can be validated against this set of project IDs.
      #
      # Returns a Set containing the accessible project IDs.
      def accessible_project_ids
        set = Set.new(bool_collection.must)
        set.merge(bool_collection.should) if bool_collection.should?
        set
      end

      # Internal: Create the boolean collection that will be used by the
      # organization project filter.
      #
      # Returns this filter's boolean collection.
      def bool_collection
        return @bool_collection if defined? @bool_collection

        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        if can_search_private_projects_for_user?
          # construct the list of project IDs to include
          visible_private_project_ids = owner.visible_projects_for(current_user).where(public: false).pluck(:id)

          # Scoped determines whether to include public/private repo projects within a owner level search.
          if scoped
            repo_ids = if owner.organization?
              owner
               .repositories_associated_with(current_user)
               .where(public: false)
               .pluck(:id)
            else
              owner
                .visible_repositories_for(current_user)
                .where(public: false)
                .pluck(:id)
            end

            # If a user can see a repo, they can see all of its projects.
            visible_private_project_ids += Project
              .where(owner_id: repo_ids)
              .owned_by_repository
              .pluck(:id)
          end
          @bool_collection.must(visible_private_project_ids)
        end

        @bool_collection
      end

      # Internal: Determine whether private projects can be included in the
      # query. Private projects can only be included if we have a currently-
      # logged-in user. If we're performing the query for an OAuth request,
      # then we also need 'repo' scope in order to search the user's accessible
      # private projects.
      #
      # Returns true if the list of accessible projects should be determined
      #   based on the permissions of +current_user+. Returns false if only
      #   public projects are accessible.
      def can_search_private_projects_for_user?
        current_user && Api::AccessControl.scope?(current_user, "repo")
      end

      private

      def owner
        return @owner if defined? @owner

        @owner = User.find_by_id(owner_id)
      end
    end
  end
end
