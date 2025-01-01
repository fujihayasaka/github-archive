# typed: true
# frozen_string_literal: true

module Search
  module Filters

    class GistFilter < ::Search::Filter
      extend T::Sig

      attr_reader :current_user

      # Create a new GistFilter.
      #
      # opts - The options Hash
      #   :current_user - the currently logged in User
      #
      def initialize(opts = {})
        super(opts)

        @field ||= :gist_id
        @keys = nil

        @current_user = options.fetch(:current_user, nil)

        bool_collection  # initialize our boolean collection
      end

      # This reason can be used when the repository filter is invalid.
      def invalid_reason
        "The listed users cannot be searched either because they do not exist or you do not have permission to view them."
      end

      # Returns `true` if the generated filter includes all public
      # repositories.
      def global?
        !bool_collection.must?
      end

      # Returns nil or a filter Hash.
      def must
        if bool_collection.must?
          build_term_filter(field, bool_collection.must)

        elsif bool_collection.should?
          { bool: {
            should: [
              { term: { public: true } },
              build_term_filter(field, bool_collection.should),
            ],
          } }

        else
          { term: { public: true } }
        end
      end

      # Returns nil or a filter Hash.
      def must_not
        build_term_filter(field, bool_collection.must_not)
      end

      # A `should` filter is not applicable to the repository filter.
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
      # accessible gist IDs that were allowed by the search criteria.
      # Results can be validated against this set of repository IDs.
      #
      # Returns a Set containing the accessible repository IDs.
      def accessible_gist_ids
        set = Set.new(bool_collection.must)
        set.merge(bool_collection.should) if bool_collection.should?
        set
      end

      # Internal: Create the boolean collection that will be used by the gist
      # filter. The :user keys from the qualifiers hash are used to construct
      # this collection. If there are no :user entries, then we try to include
      # the current user's private gist IDs.
      #
      # Returns this filter's boolean collection.
      def bool_collection
        return @bool_collection if defined? @bool_collection
        @bool_collection = ::Search::ParsedQuery::BoolCollection.new

        # construct the list of gist IDs to include
        @bool_collection.must(gist_ids_from_user(qualifiers[:user].must))
        @bool_collection.must(starred_gist_ids_from_user(qualifiers[:starred].must))
        @bool_collection.must.uniq! if @bool_collection.must?

        # construct the list of gist IDs to exclude
        @bool_collection.must_not(gist_ids_from_user(qualifiers[:user].must_not))
        @bool_collection.must_not(starred_gist_ids_from_user(qualifiers[:starred].must_not))
        @bool_collection.must_not.uniq! if @bool_collection.must_not?

        # configure the user's own private gists
        if !@bool_collection.must? && can_search_secret_gists_for_user?
          secret_gist_ids = current_user.gists.are_secret.pluck(:id)
          @bool_collection.should(secret_gist_ids)
        end

        # determine if the user passed in a @user that does not exist
        if qualifiers[:user].must?
          @valid = @bool_collection.must?
        end

        # prune `must_not` gist IDs from the `must` and `should` lists
        @bool_collection.intersect!
        @bool_collection
      end

      # Interal: Override the superclass method and make it a noop
      # implementation. Mapping the boolean collection is not applicable for
      # the gist filter.
      #
      # Returns this filter's boolean collection.
      def map_bool_collection
        bool_collection
      end

      # Internal: Return all the gist IDs that belong to the `user` that
      # the `current_user` is allowed to access.
      #
      # users - User login as a String or an Array of Strings
      #
      # Returns an Array of Gist IDs.
      sig { params(users: T.nilable(T.any(String, T::Array[String]))).returns(T::Array[Integer]) }
      def gist_ids_from_user(users)
        ids = []
        return ids if users.blank?

        User.where(login: Array(users), spammy: false).select(:id).each do |user|
          if current_user && current_user == user
            ids.concat user.gist_ids
          else
            ids.concat user.gists.are_public.pluck(:id)
          end
        end

        ids.compact!
        ids.sort
      end

      # Internal: Return all the gist IDs that were starred by the `user` that
      # the `current_user` is allowed to access.
      #
      # users - User login as a String or an Array of Strings
      #
      # Returns an Array of Gist IDs.
      sig { params(users: T.nilable(T.any(String, T::Array[String]))).returns(T::Array[Integer]) }
      def starred_gist_ids_from_user(users)
        ids = []
        return ids if users.blank?

        User.where(login: Array(users), spammy: false).select(:id).each do |user|
          if current_user && current_user == user
            ids.concat user.starred_gist_ids
          else
            ids.concat user.starred_gists.are_public.pluck(:id)
          end
        end

        ids.compact!
        ids.sort
      end

      # Internal: Determine whether private gists can be included in the
      # query. Private gists can only be included if we have a currently-
      # logged-in user.
      #
      # Returns true if the list of accessible gists should be determined
      #   based on the permissions of +current_user+. Returns false if only
      #   public gists are accessible.
      def can_search_secret_gists_for_user?
        current_user.present?
      end

    end  # GistFilter
  end  # Filters
end  # Search
