# typed: strict
# frozen_string_literal: true

module Search
  module Filters
    # A filter that combines owner_id and repo_id to target repos,
    # it's equivalent to RepositoryFilter but with a smaller list of ids.
    #
    # It requires an index with the owner_id field.
    #
    class OwnerRepoFilter < ::Search::Filter
      include GitHub::Memoizer

      # Create a new OwnerRepoFilter instance using the given options.
      #   current_user      - The current user to filter private repositories
      #   cap_filter        - The cap_filter to check business access
      #
      sig do
        params(
          qualifiers: T::Hash[Symbol, T.untyped],
          current_user: T.nilable(User),
          cap_filter: ConditionalAccess::Filter,
          resource: String,
          skip_permission_check: T::Boolean,
          field: T.nilable(Symbol),
          limit_to_repo_ids: T.nilable(T::Array[Integer]),
        ).void
      end
      def initialize(qualifiers:, current_user:, cap_filter:, resource: "metadata", skip_permission_check: false, field: :repo_id, limit_to_repo_ids: nil)
        super({ qualifiers:, field: })

        @current_user = current_user
        @cap_filter = cap_filter
        @resource = resource
        @skip_permission_check = skip_permission_check
        @limit_to_repo_ids = limit_to_repo_ids
        @filter_type = T.let("", String)

        inner_filter # Ensure we have a filter_type
      end

      delegate :must, :must?, :must_not, :must_not?, to: :inner_filter

      sig { returns(String) }
      attr_reader :filter_type

      # This filter cannot be blank, we always must generate at least public: true to avoid leaking repos
      sig { returns(T::Boolean) }
      def blank?
        false
      end

      sig { returns(T::Boolean) }
      def global?
        filter_type == "repository" && inner_repository_filter.global?
      end

      sig { returns(Integer) }
      def repo_ids_size
        case filter_type
        when "owner_visibility"
          inner_owner_visibility_filter.repo_ids_size
        when "repository"
          inner_repository_filter.repo_ids_size
        else
          0
        end
      end

      sig { params(repo: Repository).returns(T::Boolean) }
      def accessible_repository?(repo)
        case filter_type
        when "owner"
          owner_ids.include? repo.owner_id
        when "owner_visibility"
          inner_owner_visibility_filter.accessible_repository?(repo)
        when "repository"
          inner_repository_filter.accessible_repository?(repo) == true # Coerce nil to false
        end
      end

      private

      sig { returns(T.nilable(User)) }
      attr_reader :current_user

      sig { returns(ConditionalAccess::Filter) }
      attr_reader  :cap_filter

      sig { returns(String) }
      attr_reader :resource

      sig { returns(T::Boolean) }
      attr_reader :skip_permission_check

      sig { returns(T.nilable(T::Array[Integer])) }
      attr_reader :limit_to_repo_ids

      sig { returns(::Search::Filter) }
      memoize def inner_filter
        if owners.present? && owners == adminable_owners && owners == accessible_owners
          @filter_type = "owner"
          # TODO owner_id should be another field: param
          term_filter = Filters::TermFilter.new(qualifiers:, field: :owner_id, keys: OWNER_QUALIFIERS)
          term_filter.map_bool_collection { owner_ids }
          term_filter
        # TODO "filter:limit" is not used and should not be used because it ignores org:
        elsif owners == accessible_owners && owners.size == 1 # TODO Extend to many owners
          @filter_type = "owner_visibility"
          single_owner = T.must(accessible_owners.first)
          # TODO We want to depend on _calculated_ filters[:visibility], but maybe we have to use _raw_ qual[:visibility]
          Search::Filters::OwnerVisibilityFilter.new(single_owner, nil, current_user:, cap_filter:)
          # TODO Optimization: Drop the visibility filter if the owner_visibility applies it
          # TODO Better fix for both previous 2 TODOs: Optimize query removing unnecessary visibility filter
        else
          @filter_type = "repository"
          Search::Filters::RepositoryFilter.new(qualifiers:, current_user:, cap_filter:, resource:, field:, limit_to_repo_ids:)
        end
      end

      sig { returns(Search::Filters::RepositoryFilter) }
      def inner_repository_filter
        T.cast(inner_filter, Search::Filters::RepositoryFilter)
      end

      sig { returns(Search::Filters::OwnerVisibilityFilter) }
      def inner_owner_visibility_filter
        T.cast(inner_filter, Search::Filters::OwnerVisibilityFilter)
      end

      sig { returns(T::Array[User]) }
      memoize def adminable_owners
        if skip_permission_check
          owners
        elsif !can_search_private_repositories_for_user?
          []
        elsif current_user&.governed_by_oauth_application_policy?
          []
        else
          owners.filter do |owner|
            owner.adminable_by?(current_user)
          end
        end
      end

      sig { returns(T::Array[User]) }
      memoize def accessible_owners
        if skip_permission_check
          owners
        elsif !can_search_private_repositories_for_user?
          []
        elsif current_user&.governed_by_oauth_application_policy?
          []
        else
          owners.filter do |owner|
            !protected_account_logins.include?(owner.display_login)
          end
        end
      end

      OWNER_QUALIFIERS = %i(org user owner).freeze

      sig { returns(T::Array[User]) }
      memoize def owners
        owner_logins = OWNER_QUALIFIERS.map { |name| qualifiers[name].must }.compact.flatten
        owners = User.where(login: owner_logins).to_a
      end

      sig { returns(T::Array[Internal]) }
      memoize def owner_ids
        owners.map(&:id)
      end

      # Private: The account logins to exclude from results based on
      # whether the current user does not meet any of the conditional access policies
      # (e.g. SAML policy or IP allow list policy)
      sig { returns(T::Array[String]) }
      def protected_account_logins
        cap_filter.unauthorized_resources(
          current_user&.resources_for_cap_filter
        ).pluck(:login)
      end

      # Internal: Whether private repositories can be included in the results.
      sig { returns(T::Boolean) }
      def can_search_private_repositories_for_user?
        return false unless current_user
        Api::AccessControl.scope?(current_user, "repo")
      end
    end
  end
end
