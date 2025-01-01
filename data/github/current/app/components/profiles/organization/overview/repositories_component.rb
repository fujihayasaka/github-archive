# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Overview
      class RepositoriesComponent < ApplicationComponent
        include Users::RepositoryFilteringMethods
        include ProfilesHelper
        include Scientist

        ID_IN_CLAUSE_LIMIT = 1_000
        REPOSITORY_MAX_RESULTS = 10

        def initialize(profile_layout_data:, user_session:, view_as: nil)
          @profile_layout_data = profile_layout_data
          @user_session = user_session
          @view_as = view_as
        end

        attr_reader :profile_layout_data, :user_session
        delegate(
          :profile_organization,
          :organization_members,
          :adminable_by_viewer?,
          :phrase,
          :sort_order,
          :type_filter,
          :language,
          to: :profile_layout_data,
        )

        # Public: Returns a sorted list of language names that occur in the
        # repositories owned by the organization that the viewer can access.
        memoize def language_names_for_search
          language_names_for(repos_for_current_user)
        end

        def selected_language
          language
        end

        def selected_sort_order(sort_order:)
          Users::RepositoryFilteringMethods::REPOSITORY_SORT_ORDERS[sort_order] || "Last updated"
        end

        def sort_order_description(sort_order:)
          selected_sort_order(sort_order: sort_order).downcase
        end

        # Public: Whether we should be showing the language search dropdown
        def show_language_search?
          language_names_for_search.present?
        end

        def type_filters
          viewing_as_public = @view_as == "public"
          if GitHub.flipper[:view_as_public_hide_private_repos].enabled?(viewer)
            valid_type_filters(viewer: viewer, user: organization, include_private: show_new_repository_button? && !viewing_as_public, include_internal: !viewing_as_public)
          else
            valid_type_filters(viewer: viewer, user: organization, include_private: show_new_repository_button?)
          end
        end

        def user
          organization
        end

        def organization
          profile_organization
        end

        def viewer
          profile_layout_data.viewer
        end

        memoize def filtering?
          filtering_repositories?(type: type_filter, phrase: phrase, language: language, types: type_filters)
        end

        def show_header?
          show_toolbar?
        end

        def show_toolbar?
          # We can always search if there's public repos
          return true if any_public_repositories?
          # If no public repos and no user, we can't access anything
          return false unless viewer
          # Check if we can access any repos.
          !(show_no_repositories_for_admin? || show_no_repositories_for_member? || show_no_repositories_for_non_member?)
        end

        # Show results scenarios
        def show_no_results?
          no_repositories?
        end

        def show_no_repositories_for_member?
          no_repositories? && direct_or_team_member? &&
              !adminable_by_viewer?
        end

        def show_no_repositories_for_admin?
          no_repositories? && adminable_by_viewer?
        end

        def show_no_repositories_for_non_member?
          no_repositories? && !direct_or_team_member?
        end

        # Public: Returns true if this page has no repositories (due to pagination,
        # filtering, permissions, et al).
        memoize def no_repositories?
          !repositories.any?
        end

        # Public: Returns true if the organization has at least one public repository.
        def any_public_repositories?
          public_repositories_count > 0
        end

        memoize def public_repositories_count
          organization.public_repositories.count
        end

        # Internal: Is the current user a direct or team member of the current
        # organization. Memoized to prevent database roundtrips.
        #
        # Returns a Boolean.
        memoize def direct_or_team_member?
          organization.direct_or_team_member?(viewer)
        end

        def show_new_repository_button?
          can_create_repository?
        end

        def public_scope?
          type_filter == "public"
        end

        def fork_scope?
          type_filter == "fork"
        end

        memoize def repositories_scope
          if public_scope? || (@view_as == "public" && GitHub.flipper[:view_as_public_hide_private_repos].enabled?(viewer))
            organization.public_repositories
          else
            # If the org_scoped_visible_repositories_for experiment looks good, we can revisit
            # trying organization.visible_repositories_for here instead.
            organization.all_org_repos_for_user(
              viewer,
              id_in_clause_limit: ID_IN_CLAUSE_LIMIT,
            )
          end
        end

        # By default we only want to show the repositories that the org is a direct owner of, which
        # include sources and its forks. If the user actually enters a search query or selects the
        # "Fork" type, then we show all results (including forks of org repos by members)
        def repositories
          repository_includes = [
            :community_profile,
            :internal_repository,
            :mirror,
            :packages,
            :parent,
            :repository_license,
          ]
          repository_preloads = [:owner, :primary_language, :topics]
          @repositories ||= if phrase.present? || language.present? || fork_scope?
            search_repos_as(
              viewer,
              type: type_filter,
              types: type_filters,
              language: language,
              sort_order: sort_order,
              repositories_scope: Repository.includes(repository_includes).preload(repository_preloads),
            )
          else
            results = filter_repos_by_type(repositories_scope, type: type_filter, types: type_filters).
              includes(repository_includes).
              preload(repository_preloads)

            results = case sort_order
            when "name"
              results.sorted_by_name
            when "stargazers"
              results.most_starred
            else
              results.recently_updated
            end
            results
          end
        end

        private

        # Internal: The number of repositories in scope for this request. We cache
        # this value to save the cost of database roundtrips (even if the value is
        # cached in the DB).
        memoize def repositories_count
          repositories.count
        end

        # Internal: returns a repository scope that is suitable for the current user,
        # based on the user's membership within the organization and the number of
        # repositories associated with the user. Takes into consideration large
        # numbers of associated repos to prevent page slowness.
        #
        # Returns an ActiveRecord::Relation.
        memoize def repos_for_current_user
          if direct_or_team_member?
            repositories_scope
          else
            organization.public_repositories
          end
        end

        def live_search?
          !::Organization::RepositoryFilter.too_many_repos?(repositories_count)
        end

        memoize def can_create_repository?
          organization.can_create_repository?(viewer)
        end

        # Internal: Memoized copy of all repository IDs associated with the current
        # user.
        #
        # Returns an Array of Integers.
        def associated_repository_ids
          return [] unless viewer
          # rubocop:todo GitHub/DontCallAssociatedRepositoryIdsUnbounded
          @associated_repository_ids ||= viewer.associated_repository_ids
          # rubocop:enable GitHub/DontCallAssociatedRepositoryIdsUnbounded
        end

      end
    end
  end
end
