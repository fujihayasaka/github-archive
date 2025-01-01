# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # A filter that restrict search results to all the repos visible to the current user.
    #
    # It only works on the repos index as it hardcodes the repo_id and visibility fields.
    #
    class ReposUnboundedFilter < RepoIdFilter
      include GitHub::Memoizer

      # Create a new ReposUnboundedFilter instance using the given options.
      #   visibility_filter - The EnumeratedTermFilter for the visibility qualifier
      #                       It's used to optimize the filter by excluding conflicting visibilities
      #   current_user      - The current user to filter private repositories
      #   cap_filter        - The cap_filter to check business access
      #
      sig do
        params(
          visibility_filter: T.nilable(EnumeratedTermFilter),
          current_user: T.nilable(User),
          cap_filter: ConditionalAccess::Filter,
          resource: String,
        ).void
      end
      def initialize(visibility_filter, current_user:, cap_filter:, resource: "metadata")
        @visibility_filter = visibility_filter
        @current_user = current_user
        @cap_filter = cap_filter
        @resource = resource

        also_public = !exclude_visibility?("public")

        # Remember that internal repos can also be granted access individually just like private
        only_public = exclude_visibility?("private") && exclude_visibility?("internal")
        only_public = true if !can_search_private_repositories_for_user?
        repo_ids = only_public ? [] : individual_repo_ids

        # `also_internal` not used because internal repos are included through accessible_business_ids instead of adding all which visibility:internal.
        super(:repo_id, repo_ids, also_public:, also_internal: false)
      end

      sig { override.returns(T::Array[FilterHashResult]) }
      def should_clauses
        return super if exclude_visibility?("internal")
        return super if accessible_business_ids.empty?
        return super unless can_search_private_repositories_for_user?

        [*super, business_id_filter]
      end

      sig { returns(ConditionalAccess::Filter) }
      attr_reader :cap_filter
      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      # This filter cannot be blank, we always must apply it to avoid leaking other repos
      sig { override.returns(T::Boolean) }
      def blank?
        false
      end

      # This filter is global because it's unbounded
      sig { override.returns(T::Boolean) }
      def global?
        true
      end

      # Validates whether the given repo is accessible by current user
      sig { override.params(repo: Repository).returns(T::Boolean) }
      def accessible_repository?(repo)
        return true if repo.internal? && repo.business_id.present? && accessible_business_ids.include?(repo.business_id)

        super
      end

      private

      sig { returns(FilterHashResult) }
      def business_id_filter
        business_id_clause = build_term_filter(:business_id, accessible_business_ids)
        return business_id_clause if restricted_owner_ids.empty?

        { bool: {
            must: business_id_clause,
            must_not: build_term_filter(:owner_id, restricted_owner_ids),
        } }
      end

      sig { returns(T::Array[Integer]) }
      def individual_repo_ids
        return [] unless @current_user

        scope = individual_repos_scope
        return [] unless scope
        if restricted_owner_ids.any?
          scope = scope.where.not(owner_id: restricted_owner_ids)
        end

        # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
        user_access_ids = @current_user.associated_repository_ids(resource: @resource)
        # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded

        # TODO Should we limit MAX_CONSIDERED_REPOSITORY_IDS and/or MAX_REPO_FILTER_SIZE here?
        scope.where(id: user_access_ids).ids
      end

      sig { returns(T.untyped) }
      memoize def individual_repos_scope
        if exclude_visibility?("private")
          return nil if exclude_visibility?("internal")
          Repository.internal_scope
        elsif exclude_visibility?("internal")
          Repository.private_not_internal_scope
        else
          Repository.private_scope
        end
      end

      sig { returns(T::Array[Integer]) }
      memoize def accessible_business_ids
        return [] unless current_user
        # when removing idp_cap_for_web_enabled?, we can remove the extra check for is_enterprise_managed?, it was added here
        # to just see if the configurable was enabled on the business
        if T.must(current_user).is_enterprise_managed? && T.must(current_user).enterprise_managed_business&.idp_cap_for_web_enabled?
          cap_filter.authorized_resource_ids(T.must(current_user).businesses, exclude: [:ip_allowlist, :external_conditional_access_policy])
        else
          cap_filter.authorized_resource_ids(T.must(current_user).businesses, exclude: [:ip_allowlist])
        end
      end

      # Private: The owners to exclude from results based on CAP filter.
      sig { returns(T::Array[Integer]) }
      memoize private def restricted_owner_ids
        return [] unless current_user

        cap_filter.unauthorized_resources(
          current_user&.resources_for_cap_filter
        ).pluck(:id)
      end

      sig { params(visibility: String).returns(T::Boolean) }
      def exclude_visibility?(visibility)
        return false unless @visibility_filter

        bool_collection = @visibility_filter.bool_collection
        return false if bool_collection.must_not?
        return true if bool_collection.must? && !bool_collection.must.include?(visibility)
        return true if bool_collection.and_should? && !bool_collection.and_should.any? { |terms| terms.include?(visibility) }

        false
      end

      sig { returns(T::Boolean) }
      memoize def can_search_private_repositories_for_user?
        return false unless current_user
        Api::AccessControl.scope?(current_user, "repo")
      end
    end
  end
end
