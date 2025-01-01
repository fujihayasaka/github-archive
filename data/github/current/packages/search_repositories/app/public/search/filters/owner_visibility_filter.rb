# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # A filter that restrict search results to the repos of the given owner visible to the current user.
    #
    # It only works on the repos index as it hardcodes the repo_id, owner_id and visibility fields.
    #
    class OwnerVisibilityFilter < RepoIdFilter
      extend T::Sig

      # Create a new OwnerVisibilityFilter instance using the given options.
      #   owner             - The single repository owner this query is limited to
      #   visibility_filter - The EnumeratedTermFilter for the visibility qualifier
      #                       It's used to optimize the filter by excluding conflicting visibilities
      #   current_user      - The current user to filter private repositories
      #   cap_filter        - The cap_filter to check business access
      #
      sig do
        params(
          owner: User,
          visibility_filter: EnumeratedTermFilter,
          current_user: T.nilable(User),
          cap_filter: T.nilable(ConditionalAccess::Filter),
          resource: String,
        ).void
      end
      def initialize(owner, visibility_filter, current_user:, cap_filter:, resource: "metadata")
        @owner = owner
        @visibility_filter = visibility_filter
        @current_user = current_user
        @cap_filter = cap_filter
        @resource = resource

        private_repo_ids = exclude_visibility?("private") ? [] : single_owner_private_repo_ids
        also_internal = exclude_visibility?("internal") ? false : business_access_granted?
        also_public = !exclude_visibility?("public")

        super(:repo_id, private_repo_ids, also_public:, also_internal:)
      end

      sig { returns(FilterHashResult) }
      def must
        [build_term_filter(:owner_id, @owner.id), super].compact
      end

      # This filter cannot be blank, we always must apply it to avoid leaking other repos
      sig { returns(T::Boolean) }
      def blank?
        false
      end

      # This filter is never global as there's always an owner_id clause
      sig { returns(T::Boolean) }
      def global?
        false
      end

      # Validates whether the given repo is accessible by current user,
      # checking its visibility and owner
      sig { params(repo: Repository).returns(T::Boolean) }
      def accessible_repository?(repo)
        return false unless repo.owner_id == @owner.id
        return false unless super
        repo.readable_by?(@current_user)
      end

      private

      sig { returns(T::Boolean) }
      def business_access_granted?
        accessible_business_ids.include?(@owner.business&.id)
      end

      sig { returns(T::Array[Integer]) }
      def single_owner_private_repo_ids
        return [] unless @current_user
        return [] unless @owner.present?
        # If cap_filter is not provided, we relax security. This is risky,
        # but there are usages still relying in user_session that we need to keep working
        # like OrganizationSecurityConfigurationJob
        # There are 2 options:
        # 1. Every call that comes from a user request MUST provide cap_filter
        # 2. Jobs may call queries without cap_filter, but they are responsible to make their own security enforcement
        return [] if @cap_filter && @owner.business && !business_access_granted?

        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        user_private_ids = @current_user.associated_repository_ids(resource: @resource)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        org_private_ids = Repository.private_scope.where(owner_id: @owner.id).ids

        result = user_private_ids & org_private_ids
        granted_private_ids = ProgrammaticActor::RepositoryFilter.perform(
          actor: @current_user,
          repository_ids: result,
          resource: @resource,
        )

        result & granted_private_ids
      end

      sig { returns(T::Array[Integer]) }
      def accessible_business_ids
        return [] unless @current_user.present?
        return [] unless @cap_filter.present?

        @cap_filter.authorized_resource_ids(@current_user.businesses)
      end

      sig { params(visibility: String).returns(T::Boolean) }
      def exclude_visibility?(visibility)
        bool_collection = @visibility_filter.bool_collection
        return false if bool_collection.must_not?
        return true if bool_collection.must? && !bool_collection.must.include?(visibility)
        return true if bool_collection.and_should? && !bool_collection.and_should.any? { |terms| terms.include?(visibility) }

        false
      end
    end
  end
end
