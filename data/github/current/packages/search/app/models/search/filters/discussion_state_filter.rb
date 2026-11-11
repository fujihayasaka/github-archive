# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # Public: The DiscussionStateFilter is used to limit discussion search results to valid discussion states.
    #
    # If the user is not logged in, they cannot search for draft discussions. While the enforcement that users can
    # only query for their own draft discussions is done at a higher level (e.g. the DiscussionQuery), we use
    # this filters validity check to ensure that anonymous users cannot query for draft discussions.
    class DiscussionStateFilter < TermFilter
      include GitHub::Memoizer

      INVALID_STATE_ERROR_MESSAGE = T.let("The listed states cannot be searched because the states do not exist.".freeze, String)
      MISSING_CURRENT_USER_ERROR_MESSAGE = T.let("You must be logged in to search for these discussions.".freeze, String)
      MISSING_AUTHOR_ERROR_MESSAGE = T.let("You cannot search for draft discussions without an author.".freeze, String)
      UNAUTHORIZED_DRAFT_DISCUSSIONS_ERROR_MESSAGE = T.let("You can only search for your own draft discussions.".freeze, String)
      UNAUTHORIZED_SCHEDULED_DISCUSSIONS_ERROR_MESSAGE = T.let("You do not have permission to search for scheduled discussions.".freeze, String)

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(T.nilable(Repository)) }
      attr_reader :current_repository

      sig { returns(T::Array[String]) }
      attr_reader :states

      # Create a new StateFilter.
      #
      # opts - The options Hash
      #   :current_user - the user that this category filter should be scoped to
      sig { params(opts: T.untyped).void }
      def initialize(opts = {})
        super(opts)

        @field = T.let(opts[:field].presence || :state, Symbol)
        @current_user = T.let(opts[:current_user], T.nilable(User))
        @current_repository = T.let(opts[:current_repository], T.nilable(Repository))
        @states = T.let(::Discussion.states.keys.collect(&:to_s), T::Array[String])
        @valid = T.let(true, T::Boolean)
        @invalid_reason = T.let(nil, T.nilable(String))

        map_bool_collection
      end

      # Internal: Take the boolean collection and convert all the values into
      # category IDs if possible.
      #
      # Returns this filter's boolean collection.
      sig { returns(T.untyped) }
      memoize def map_bool_collection
        validate_states!
        validate_draft_state!
        validate_scheduled_state!

        bool_collection.intersect!
        bool_collection
      end

      private

      sig { void }
      def validate_states!
        original_must = bool_collection.must?
        original_must_not = bool_collection.must_not?
        return unless original_must || original_must_not

        # Only allow valid states
        bool_collection.map_all! do |state|
          states.include?(state) ? state : nil
        end
        bool_collection.uniq!

        # Did the states we're querying for change?
        must_changed = original_must != bool_collection.must?
        must_not_changed = original_must_not != bool_collection.must_not?
        return unless must_changed || must_not_changed

        invalid!(INVALID_STATE_ERROR_MESSAGE)
      end

      # Users can only query for their own draft discussions.
      sig { void }
      def validate_draft_state!
        return unless bool_collection.must&.include?("draft")
        user = current_user
        # If the user is not logged in, they cannot search for draft discussions at all.
        if user.blank?
          invalid!(MISSING_CURRENT_USER_ERROR_MESSAGE)
          return
        end

        author = qualifiers[:author]&.must
        if author.blank?
          invalid!(MISSING_AUTHOR_ERROR_MESSAGE)
          return
        end

        # If the user is logged in, the only user they can search for draft discussions is themselves.
        if author.uniq != [user.display_login]
          invalid!(UNAUTHORIZED_DRAFT_DISCUSSIONS_ERROR_MESSAGE)
        end
      end

      # Users can only query for scheduled discussions when they have at least maintain access to the repository.
      sig { void }
      def validate_scheduled_state!
        return unless bool_collection.must&.include?("scheduled")

        if current_user.blank?
          invalid!(MISSING_CURRENT_USER_ERROR_MESSAGE)
        elsif (repository = current_repository)
          unless repository.writable_by?(current_user)
            invalid!(UNAUTHORIZED_SCHEDULED_DISCUSSIONS_ERROR_MESSAGE)
          end
        end
      end

      sig { params(message: String).void }
      def invalid!(message)
        @invalid_reason = message
        @valid = false
      end
    end
  end
end
