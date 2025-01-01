# typed: true
# frozen_string_literal: true

module Profiles
  class StarsController < ApplicationController
    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Mysql5,
      ApplicationRecord::Configurations,
      ApplicationRecord::Collab,
      ApplicationRecord::Repositories,
      ApplicationRecord::Mysql2,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Spokes,
      ApplicationRecord::Ballast,
      ApplicationRecord::Billing,
      ApplicationRecord::Iam,
      only: [:index]

    depends_on_clusters ApplicationRecord::Copilot,
      only: [:index],
      optional: true

    STAR_SORT_FIELD_MAPPING = {
      "updated" => "pushed_at",
      "stars" => "watcher_count",
      "created" => "created_at",
    }.freeze
    STARRED_TOPICS_LIMIT = 10

    include ProfilesHelper
    include Registry::QueryHelper
    include UserContributionsHelper

    around_action :record_profile_stats, only: :index
    before_action :ensure_profile_visible
    skip_before_action :cap_pagination, only: :index

    set_statsd_sample_rate 0.01, only: :index

    javascript_bundle :profile
    stylesheet_bundle :profile

    def index
      return render_404 if this_user.mannequin?

      if this_user.organization?
        return render_404
      end

      respond_to do |format|
        format.html do
          instrument_hydro

          render_user_profile
        end
      end
    end

    private

    def render_user_profile
      starred_repos, starred_repository_count, over_repo_stars_limit, page_info = load_data(
        language: params[:language],
        repo_type: params[:type],
      )
      GitHub::PrefillAssociations.prefill_associations(starred_repos, [:owner, :primary_language])
      if logged_in?
        owners = starred_repos.map(&:owner)
        GitHub::PrefillAssociations.prefill_batch_method(owners + [this_user], :sponsorable?)
        GitHub::PrefillAssociations.prefill_batch_method(owners, :sponsored_by_viewer?, current_user)
        GitHub::PrefillAssociations.prefill_batch_method(starred_repos, :starred_by?, current_user)
      end

      user_lists = UserLists::ListCollection.new(
        this_user.lists,
        sorting_strategy: user_lists_sorting_strategy,
        owner: this_user
      )

      render "users/tabs/stars/index", locals: {
        starred_repositories: starred_repos,
        starred_repository_count: starred_repository_count,
        starred_topics: this_user.starred_topics(limit: STARRED_TOPICS_LIMIT + 1),
        layout_data: Profiles::User::LayoutData.preload(
          profile_user: this_user,
          viewer: current_user,
          active_tab: :stars,
        ),
        user_lists: user_lists,
        over_repo_stars_limit: over_repo_stars_limit,
        repo_page_info: page_info,
      }
    end

    def stars_order_by
      default_field = "created_at"
      default_direction = "DESC"
      field = STAR_SORT_FIELD_MAPPING[params[:sort]] || default_field
      direction = (params[:direction] || default_direction).upcase

      field = default_field unless STAR_SORT_FIELD_MAPPING.values.include?(field)
      direction = default_direction unless %w[ASC DESC].include?(direction)

      { field: field, direction: direction }
    end

    def instrument_hydro
      GlobalInstrumenter.instrument(
        "user_profile.page_view",
        has_organization_memberships: this_user.organizations.any?,
        profile_user: this_user,
        profile_viewer: current_user,
        scoped_org_id: scoped_organization&.id,
        selected_tab: :STARS,
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

      GitHub.dogstats.distribution("user.profile.stars.request", duration * 1000, tags: tags)
    end

    def search_query
      return @search_query if defined? @search_query
      raw_query = params[:q]
      raw_query if raw_query.is_a?(String)
    end

    def target_for_conditional_access
      return :no_target_for_conditional_access unless this_user.present? # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
      this_user
    end

    def load_data(language:, repo_type:)
      values = {
        viewer: current_user,
        unauthorized_organization_ids: cap_filter.unauthorized_resource_ids(current_user&.organizations),
        oauth_app: nil,
        permission: Platform::Authorization::Permission.new(
          viewer: current_user,
          origin: Platform::ORIGIN_INTERNAL
        ),
        mask: Platform::SchemaRuntimeMask.new(
          :public,
          environment: GitHub.runtime.current
        )
      }

      # Using resolvers outside of a query and context is not suppported by the graphql gem public API
      # There we make use of the internal API to provide a valid query. See https://github.com/rmosolgo/graphql-ruby/issues/5040#issuecomment-2253136394
      context = Platform::Context.new(query: GraphQL::Query.new(Platform::Schema, "{ __typename }"), values: values)

      resolver = Platform::Resolvers::StarredRepositories.new(
        object: this_user,
        context: context,
        field: nil,
      )
      connection_wrapper = resolver.resolve(
        query: search_query,
        language: language,
        order_by: stars_order_by,
        type: repo_type,
        user_session: user_session,
        **graphql_pagination_params(page_size: Star.per_page)
      )

      # class.type gets the connection class from the resolver
      # new is protected on connections, so we use send because we're hackers
      connection = resolver.class.type.send(:new, connection_wrapper, nil)

      Platform::Security::RepositoryAccess.with_viewer(current_user) do
        Promise.all([
          connection.nodes,
          connection.total_count,
          connection.is_over_limit,
          connection_wrapper.page_info,
        ]).sync
      end
    rescue Platform::Errors::Cursor
      [[], 0, false, EmptyPageInfo.new]
    end

    def user_lists_sorting_strategy
      if logged_in? && params[:user_lists_sort].blank?
        user_preference = current_user.settings.get(:user_profile_lists_sorting_strategy)
        return UserLists::SortingStrategy.unserialize(user_preference)
      end

      UserLists::SortingStrategy.new(params[:user_lists_sort], params[:user_lists_direction])
    end

    class EmptyPageInfo
      def has_previous_page?
        false
      end

      def has_next_page?
        false
      end

      def start_cursor
        nil
      end

      def end_cursor
        nil
      end

      def total_count
        0
      end
    end
  end
end
