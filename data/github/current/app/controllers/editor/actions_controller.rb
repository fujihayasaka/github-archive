# typed: false
# frozen_string_literal: true

module Editor
  class ActionsController < ApplicationController
    include Platform::Helpers::MarketplaceSearchHelper
    include Search::RepositoryActionIconHelper

    layout false

    helper_method :pagination_url, :search_placeholder

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::Collab,
      ApplicationRecord::GitHubModels,
      only: [:index]

    depends_on_clusters ApplicationRecord::Mysql1,
      ApplicationRecord::Repositories,
      ApplicationRecord::Spokes,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      only: [:show]

    FEATURED_ACTIONS_LIMIT = 5

    SEARCH_RESULTS = 10

    def index
      category_slug = params.fetch(:category, "")
      search_query = params.fetch(:query, "")

      if category_slug.present?
        category = Marketplace::Category.find_by(slug: category_slug)
        return head :not_found if category.nil?
      end

      if category_slug.blank? && search_query.blank?
        respond_with_featured
      else
        respond_with_search_results(category: category, search_query: search_query, category_slug: category_slug)
      end
    end

    def show
      action = RepositoryAction.find_by(id: params[:action_id])

      respond_to do |format|
        format.html { render "editor/actions/show", locals: { action: action } }
        format.html_fragment { render "editor/actions/show", locals: { action: action } }

        format.json do
          return head :not_found if action.nil?
          return head :not_found unless react_editor_actions_sidebar_enabled?

          render json: serialize_action_detail(action)
        end
      end
    end

    private

    def respond_with_featured
      actions = featured_actions

      respond_with_html_or_json(
        html: -> {
          render "editor/actions/index", formats: :html, locals: {
            featured_actions: actions,
            seed: seed,
            categories: featured_categories,
          }
        },
        json: -> {
          {
            featuredActions: actions.map { |action| serialize_action(action) },
            categories: featured_categories,
            seed: seed,
          }
        },
      )
    end

    def respond_with_search_results(category:, search_query:, category_slug:)
      variables = {
        searchQuery: search_query,
        categorySlug: category_slug,
        searchType: "repository-action",
        items_per_page: SEARCH_RESULTS,
      }
      query = async_formulate_query?(variables).sync
      action_results = get_execute_query(query, variables, current_page).execute

      # Prefill data needed to render each item
      Promise.all(action_results.map(&:repository_action).map(&:async_verified_owner?)).sync

      respond_with_html_or_json(
        html: -> {
          render "editor/actions/search", formats: :html, locals: {
            action_results: action_results,
            category_name: category&.name
          }
        },
        json: -> {
          {
            results: action_results.map { |result| serialize_action(result.repository_action) },
            categoryName: category&.name,
            totalCount: action_results.count,
            pagination: {
              previousPage: action_results.previous_page,
              nextPage: action_results.next_page,
            },
          }
        },
      )
    end

    def respond_with_html_or_json(html:, json:)
      respond_to do |format|
        # we need to support both formats for the Rails-rendered sidebar:
        # - <include-fragment> sends `Accept: text/html`,
        # - <remote-input> sends `Accept: text/fragment+html`
        format.html(&html)
        format.html_fragment(&html)

        format.json do
          return head :not_found unless react_editor_actions_sidebar_enabled?

          render json: json.call
        end
      end
    end

    # CAP is not needed because this controller returns actions available on the public marketplace
    def target_for_conditional_access
      :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    end

    def seed # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
      @seed ||= params.fetch(:seed, rand(4294967295)).to_i
    end

    def featured_actions
      featured_actions = RepositoryAction.
        featured.
        listed.
        preload(repository: [:owner]).
        order(Arel.sql("RAND(#{seed})")).
        limit(FEATURED_ACTIONS_LIMIT).
        sort_by { |action| action.repository.stargazer_count }.
        reverse
    end

    def pagination_url(page: nil)
      pagination_params = {
        category: params[:category],
        page: page,
        seed: params[:seed],
      }.compact
      editor_actions_search_url(pagination_params)
    end

    def search_placeholder(category: nil)
      if category.present?
        "Search Marketplace for #{category.capitalize} Actions"
      else
        "Search Marketplace for Actions"
      end
    end

    memoize def react_editor_actions_sidebar_enabled?
      FeatureFlag.vexi.enabled?(:react_editor_actions_sidebar, current_user, default: false)
    end

    def serialize_action(action)
      {
        id: action.id,
        name: action.name,
        description: action.description,
        ownerLogin: action.repository.owner_display_login,
        verifiedOwner: action.verified_owner?,
        color: action.color,
        iconName: action.icon_name,
        iconColor: action.icon_color,
        iconSvg: svg_icon_string(action.icon_name, owner: action.repository.owner_display_login),
        stargazerCount: action.repository.stargazer_count,
        slug: action.slug,
        marketplacePath: marketplace_action_path(action.slug),
      }
    end

    def serialize_action_detail(action)
      serialize_action(action).merge(
        latestVersion: action.latest_tag_or_default_branch,
        releases: serialize_releases(action),
      )
    end

    def serialize_releases(action)
      releases = action.published_releases_workflow_snippet.map do |entry|
        {
          version: entry[:release].tag_name,
          snippet: entry[:example],
        }
      end

      if releases.empty?
        releases = [{
          version: action.latest_tag_or_default_branch,
          snippet: action.default_branch_workflow_snippet,
        }]
      end

      releases
    end

    def featured_categories
      # Hard-code the list of categories for now, see https://github.com/github/c2c-actions-experience/issues/1702
      [
        {
          name: "Code quality",
          slug: "code-quality",
        },
        {
          name: "Continuous integration",
          slug: "continuous-integration",
        },
        {
          name: "Deployment",
          slug: "deployment",
        },
        {
          name: "Monitoring",
          slug: "monitoring",
        },
        {
          name: "Project management",
          slug: "project-management",
        },
        {
          name: "Testing",
          slug: "testing",
        },
      ]
    end
  end
end
