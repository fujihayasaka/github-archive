# typed: true
# frozen_string_literal: true

module Profiles
  module Organization
    module Overview
      module Repositories
        class ResultsComponent < ApplicationComponent
          include Users::RepositoryFilteringMethods

          TOPIC_NAMES_PER_REPO = 7
          REPOSITORY_MAX_RESULTS = 10

          def initialize(profile_layout_data:, repositories:)
            @profile_layout_data = profile_layout_data
            @repositories = repositories
          end

          attr_reader :profile_layout_data, :repositories

          delegate(
            :profile_organization,
            :organization_members,
            :adminable_by_viewer?,
            :phrase,
            :sort_order,
            :type_filter,
            :default_type_filter,
            :language,
            :viewer,
            to: :profile_layout_data,
          )

          def organization
            profile_organization
          end

          memoize def results
            # Cache results to avoid database roundtrips
            repositories.first(REPOSITORY_MAX_RESULTS).to_a
          end

          memoize def total_entries
            # Cache results count to avoid database roundtrips
            (repositories.try(:total_entries) || repositories.count)
          end

          memoize def filtering?
            filtering_repositories?(type: type_filter, phrase: phrase, language: language,
                                                 types: type_filters)
          end

          def package_registry_enabled?
            # This is supposed to return `PackageRegistryHelper.show_packages?` but is disabled
            # until we find a fast way of fetching the package count for all packages types (v1 Registry and Container Registry)
            # For reference: https://github.com/github/c2c-package-registry/issues/2399

            false
          end

          def selected_sort_order(sort_order:)
            Users::RepositoryFilteringMethods::REPOSITORY_SORT_ORDERS[sort_order] || "Last updated"
          end

          def sort_order_description(sort_order:)
            selected_sort_order(sort_order: sort_order).downcase
          end

          # Individual repository helpers
          def pull_request_count_for(repository_id)
            has_pull_request = true
            open_issue_and_pr_counts[[repository_id, has_pull_request]].to_i
          end

          def issue_count_for(repository_id)
            has_pull_request = false
            open_issue_and_pr_counts[[repository_id, has_pull_request]].to_i
          end

          def network_count_for(repository)
            count = public_fork_counts_for_public_roots[repository.id] ||
              full_network_counts[repository.source_id]

            count.to_i
          end

          def topic_names_for(repository_id)
            topic_names_by_repository_id[repository_id] || []
          end

          private

          memoize def public_fork_counts_for_public_roots
            Repository.public_fork_counts_for_public_roots_for(
              network_ids: results.pluck(:source_id),
            )
          end

          memoize def full_network_counts
            Repository.full_network_counts_for(
              source_ids: results.pluck(:source_id),
            )
          end

          memoize def open_issue_and_pr_counts
            if FeatureFlag.vexi.enabled?(:issue_dependency_removal, default: false)
              Issues.domain.open_issue_and_pr_counts(repository_ids: results.pluck(:id))
            else
              Repository.open_issue_and_pr_counts(repository_ids: results.pluck(:id))
            end
          end

          memoize def topic_names_by_repository_id
            RepositoryTopic.names_for(
              repository_ids: results.pluck(:id),
              limit_per_repo: TOPIC_NAMES_PER_REPO,
            )
          end

          def type_filters
            valid_type_filters(viewer: viewer, user: organization, include_private: show_new_repository_button?)
          end

          def clear_filter_params
            default_type_filter != "all" ? { type: "all" } : {}
          end

          memoize def show_new_repository_button?
            organization.can_create_repository?(current_user)
          end

          def selected_language
            helpers.get_selected_language(language)
          end

          def list_analytics_attributes(target)
            analytics_click_attributes(
              category: "profiles:org_repos_list",
              action: "click",
              label: "target:#{target}"
            )
          end
        end
      end
    end
  end
end
