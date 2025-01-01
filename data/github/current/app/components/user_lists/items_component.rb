# typed: true
# frozen_string_literal: true

module UserLists
  class ItemsComponent < ApplicationComponent
    PER_PAGE = 30

    # list - a UserList
    # page - Integer page number for which page of items in the UserList should be shown
    # visible_list_item_repositories - Array of all Repository records in the list (so not paginated or limited),
    #                                  already filtered to those that the current user can see; if omitted,
    #                                  will be calculated
    def initialize(list:, page: 1, visible_list_item_repositories: nil)
      @list = list
      @page = page
      @visible_list_item_repositories = visible_list_item_repositories
    end

    private

    attr_reader :list, :page

    delegate :cap_filter, to: :helpers

    def render?
      list.present? && page.present? && page > 0
    end

    # Private: All the repositories in the list that the currently authenticated user can see. Nothing has
    # been preloaded on these repositories and they are not paginated.
    memoize def visible_list_item_repositories
      @visible_list_item_repositories || list.item_repositories_visible_to(
        viewer: current_user,
        cap_filter: cap_filter,
      )
    end

    # Private: The repositories in the list that the currently authenticated user can see, paginated and
    # with additional relations preloaded to avoid n+1 queries.
    memoize def paginated_list_item_repositories
      prefetch_repo_relations(paginate_repos(visible_list_item_repositories))
    end

    def paginate_repos(repos)
      repos.paginate(page: page, per_page: PER_PAGE)
    end

    def prefetch_repo_relations(repos)
      GitHub::PrefillAssociations.prefill_associations(repos, [:owner, :primary_language])
      GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, current_user)
      GitHub::PrefillAssociations.prefill_batch_method(repos, :sponsorable_owner?)
      GitHub::PrefillAssociations.prefill_batch_method(repos, :owner_sponsored_by_viewer?, current_user)

      # Preload :all_forks_count for private repositories to prevent queries from Repository#forks_count. For public
      # repositories, this is a direct attribute read, so no preloading is necessary.
      private_repos = repos.select(&:private?)
      if private_repos.any?
        GitHub::PrefillAssociations.prefill_batch_method(private_repos, :all_forks_count)
      end

      repos
    end
  end
end
