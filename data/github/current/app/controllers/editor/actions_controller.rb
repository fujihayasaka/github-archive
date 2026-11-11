# typed: false
# frozen_string_literal: true

module Editor
  class ActionsController < ApplicationController
    include Platform::Helpers::MarketplaceSearchHelper

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
        render "editor/actions/index", formats: :html, locals: {
          featured_actions: featured_actions,
          seed: seed,
          categories: featured_categories,
        }
      else
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

        render "editor/actions/search", formats: :html, locals: {
          action_results: action_results,
          category_name: category&.name
        }
      end
    end

    def show
      action = RepositoryAction.find_by(id: params[:action_id])
      render "editor/actions/show", locals: { action: action }
    end

    private

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
