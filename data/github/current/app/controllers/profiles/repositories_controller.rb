# typed: true
# frozen_string_literal: true

module Profiles
  class RepositoriesController < ApplicationController
    include ProfilesHelper
    include UserContributionsHelper
    include Search::RepositoryQueryFilters
    include GitHub::Memoizer
    include Repositories::Domain::Provider

    around_action :record_profile_stats, only: :index
    before_action :ensure_user_visible, only: :index
    before_action :require_user, only: :index
    skip_before_action :cap_pagination, only: :index

    set_statsd_sample_rate 0.01, only: :index

    javascript_bundle :profile
    stylesheet_bundle :profile

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Repositories,
      ApplicationRecord::Collab,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Spokes,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    def index
      return render_404 if this_user.mannequin?

      respond_to do |format|
        format.html do
          instrument_hydro

          if request.xhr? && !pjax?
            render_user_repositories_tab
          else
            render_repository_index
          end
        end
      end
    end

    def selected_sort_order(sort_order:) # rubocop:todo GitHub/UseRestfulActions
      Users::RepositoryFilteringMethods::REPOSITORY_SORT_ORDERS[sort_order] || "Last updated"
    end
    helper_method :selected_sort_order

    def sort_order_description(sort_order:) # rubocop:todo GitHub/UseRestfulActions
      selected_sort_order(sort_order: sort_order).downcase
    end
    helper_method :sort_order_description

    private

    def render_repository_index
      if view_private_profile?
        render "users/tabs/repositories/private/index", locals: {
          repositories: fetch_repositories(paginated_repositories),
          paginated_repositories: paginated_repositories,
          ar_user: this_user,
          previewing: preview_private_profile?,
          private_profile: view_private_profile?,
          layout_data: Profiles::User::LayoutData.preload(
            profile_user: this_user,
            viewer: current_user,
            active_tab: :repositories,
          ),
        }
      else
        render "users/tabs/repositories/index", locals: {
          repositories: fetch_repositories(paginated_repositories),
          paginated_repositories: paginated_repositories,
          ar_user: this_user,
          previewing: preview_private_profile?,
          private_profile: view_private_profile?,
          layout_data: Profiles::User::LayoutData.preload(
            profile_user: this_user,
            viewer: current_user,
            active_tab: :repositories,
          ),
        }
      end
    end

    def render_user_repositories_tab
      render partial: "users/tabs/repositories", locals: {
        private_profile: view_private_profile?,
        repositories: fetch_repositories(paginated_repositories),
        paginated_repositories: paginated_repositories
      }
    end

    def order_by
      if this_user.try(:private_profile_for?, current_user)
        { direction: "asc", field: "name" }
      else
        repositories_query_sort(sort: repository_sort).transform_values(&:downcase)
      end
    end

    def order_repositories_on_page(repos)
      order_method = Platform::Enums::RepositoryOrderField.values[order_by[:field].upcase]&.value
      return repos unless order_method

      # This column has been marked for rename. We need to refer to the new name here as this
      # accesses the model's attribute, not the database column. This can go when the rename
      # is complete.
      order_method = "stargazer_count" if order_method == "watcher_count"

      repos = repos.sort_by do |repo|
        # Since pushed_at can be `nil`, fall back to created_at if needed
        if order_method == "pushed_at"
          repo.pushed_at || repo.created_at
        elsif order_method == "name"
          repo.name.downcase
        else
          repo.send(order_method)
        end
      end

      repos = repos.reverse if order_by[:direction] == "desc"
      repos
    end

    def paginated_repositories # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      return @paginated_repositories if defined?(@paginated_repositories)

      @paginated_repositories = if search_query.present? || params[:language].present?
        Search::Queries::RepoQuery.new(phrase: search_phrase(search_query, repository_type&.downcase, this_user.login), # rubocop:todo GitHub/DoNotAllowLogin https://github.com/github/proxima/issues/1194
          source_fields: false, star_search: false,
          include_forks: true, current_user: current_user,
          star_user: this_user, language: params[:language],
          page: current_page || 1, per_page: Repository.per_page,
          sort: search_sort(order_by)).execute
      else
        sort = case order_by[:field]&.downcase
        when "stargazers"
          direction = GH::Pagination::Sort::Direction::DESC
          ::Repositories::SortBy::WatcherCountThenId
        when "name"
          direction = GH::Pagination::Sort::Direction::ASC
          ::Repositories::SortBy::NameThenId
        else
          direction = GH::Pagination::Sort::Direction::DESC
          ::Repositories::SortBy::PushedAtThenId
        end

        repos = repositories_domain.by_owner_and_type_for_actor(
          owner: this_user,
          type: repository_type ? Repositories::RepositoryType.deserialize(repository_type&.downcase) : nil,
          pagination: GH::Pagination::Offset.new(page: current_page, per_page: Repository.per_page),
          sort:,
          direction:,
          public_only: view_private_profile?
        )

        GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, current_user)
        GitHub::PrefillAssociations.prefill_associations(repos, [
          :community_profile,
          :internal_repository,
          :mirror,
          :parent,
          :network,
          :repository_licenses,
          :owner,
          :primary_language,
          :topics
        ])

        repos
      end
    end

    def domain_actor
      current_user
    end

    def fetch_repositories(paginated_repos)
      # If this flipper is enabled, then we've already retrieved a page of repos, w/ prefilled associations, in
      # the correct order, so no need to do the rest of this
      return paginated_repos unless paginated_repos.is_a?(Search::Results)

      ids = paginated_repos.results.map { |r| r["_id"] }

      repository_includes = [
        :community_profile,
        :internal_repository,
        :mirror,
        :parent,
        :network,
        :repository_licenses,
      ]
      repository_preloads = [:owner, :primary_language, :topics]

      repos = Repository.where(id: ids)
        .includes(repository_includes)
        .preload(repository_preloads)
        .to_a

      GitHub::PrefillAssociations.prefill_batch_method(repos, :starred_by?, current_user)

      order_repositories_on_page(repos)
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: :REPOSITORIES,
      )

      GlobalInstrumenter.instrument(
        "user_profile.repositories.page_view",
        profile_user: this_user,
        profile_viewer: current_user,
        is_organization: false,
        selected_sort: repository_sort,
      )
    end

    def record_profile_stats
      return yield unless logged_in? && this_user && !this_user.organization?

      before = Time.now
      yield
      duration = Time.now - before

      tags = ProfilesController::ShowProfileStats.tags(
        activity_overview_rendered: activity_overview_enabled?,
        subject_user: this_user,
        viewer: current_user,
      )

      GitHub.dogstats.distribution("user.profile.repositories.request", duration * 1000, tags: tags)
    end

    def search_query
      return @search_query if defined? @search_query
      raw_query = params[:q]
      raw_query if raw_query.is_a?(String)
    end

    def repository_type
      return unless params[:type]&.respond_to?(:upcase)

      type = params[:type].upcase
      valid_types = Platform::Enums::RepositoryType.values.values.map(&:graphql_name)
      unless valid_types.include?(type)
        type = nil
        params[:type] = nil
      end
      type
    end

    sig { returns(T.nilable(String)) }
    def repository_sort
      sort_param = params[:sort]
      return unless sort_param.present?
      sort = sort_param.to_s.upcase

      Platform::Enums::RepositoryOrderField.values[sort]&.graphql_name
    end

    def repositories_query_sort(sort:)
      query_sort = case sort
      when "STARGAZERS"
        { field: "STARGAZERS", direction: "DESC" }
      when "NAME"
        { field: "NAME", direction: "ASC" }
      else
        { field: "PUSHED_AT", direction: "DESC" }
      end
      query_sort
    end

    def require_user
      if this_user.nil?
        render_404
      elsif this_user.organization?
        redirect_to user_path(this_user)
      end
    end

    # Render a 404 if there is no user or the user is hidden from the viewer
    def ensure_user_visible
      return if this_user && !this_user.hide_from_user?(current_user)
      render_404
    end

    def target_for_conditional_access
      # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      return :no_target_for_conditional_access unless this_user.present?
      # rubocop:enable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def view_private_profile?
      this_user.private_profile? &&
        ((this_user == current_user && preview) ||
        current_user != this_user)
    end

    def preview_private_profile?
      this_user == current_user && preview
    end

    memoize def preview
      ActiveRecord::Type::Boolean.new.deserialize(params[:preview])
    end
  end
end
