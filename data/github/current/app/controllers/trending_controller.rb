# typed: true
# frozen_string_literal: true

class TrendingController < ApplicationController
  include Trending::TrendingMethods
  include ExploreHelper

  # cap_bypass:to_fix This controller skips CAP. it 404s in Proxima but looks like popular_developers and popular_repositories queries are not segregated by enterprise anyways
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  # :site bundle dependency should be transitioned to only :explore
  stylesheet_bundle :site
  stylesheet_bundle :explore

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes,
    ApplicationRecord::IssuesPullRequests,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    only: [:developers]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :developers],
    optional: true

  before_action :ensure_not_multitenant_enterprise, only: [:index, :developers]

  def index
    context_region_preset context_region

    if GitHub.enterprise?
      @popular = popular_repositories

      view = create_view_model(
        Trending::ListView,
        language: language,
        since: since,
        context: IndexContext,
      )
      render "trending/index", locals: {
        view: view,
        trending_depreciation_enabled: trending_depreciation_enabled?
      }
    else
      repositories = ExploreFeed::Trending::Repository.all(
        language: language,
        period: since,
        spoken_language_code: spoken_language_code,
      )
      preload_repo_associations(repositories.to_a)

      sponsorable_ids = nil
      is_sponsoring_by_sponsorable_id = {}
      if GitHub.sponsors_enabled?
        repo_owner_ids = repositories.pluck(:owner_id)
        sponsorable_ids = Set.new(User.sponsorable_user_ids_from(repo_owner_ids, viewer: current_user))

        if logged_in?
          is_sponsoring_by_sponsorable_id = Sponsorship.sponsor_status_by_sponsorable_id(
            sponsorable_ids: sponsorable_ids,
            sponsor_id: current_user.id,
          )
        end
      end

      starred_by_viewer = if logged_in?
        current_user.starred_repository_ids(repo_ids: repositories.map(&:id)).to_set
      else
        Set.new
      end

      render(
        "trending/index_redesign",
        locals: {
          language: language,
          repositories: repositories,
          sponsorable_ids: sponsorable_ids,
          is_sponsoring_by_sponsorable_id: is_sponsoring_by_sponsorable_id,
          starred_by_viewer: starred_by_viewer,
          since: since,
          spoken_language_code: spoken_language_code,
          context: IndexContext,
          trending_depreciation_enabled: trending_depreciation_enabled?,
          stars_since: Stars.domain.repositories_stars_since(repository_ids: repositories.map(&:id), period: since.to_sym),
        },
      )
    end
  end

  def developers # rubocop:todo GitHub/UseRestfulActions
    context_region_preset context_region

    if GitHub.enterprise?
      @popular = popular_developers

      view = create_view_model(
        Trending::ListView,
        context: DevelopersContext,
        language: language,
        since: since,
      )
      render "trending/developers", locals: {
        view: view,
        trending_depreciation_enabled: trending_depreciation_enabled?
      }
    else
      developers = ExploreFeed::Trending::Developer.all(
        language: language,
        period: since,
        sponsorable: sponsorable_only?,
      )

      preload_developer_associations(developers)

      render(
        "trending/developers_redesign",
        locals: {
          developers: developers,
          language: language,
          since: since,
          sponsorable: sponsorable_only?,
          context: DevelopersContext,
          trending_depreciation_enabled: trending_depreciation_enabled?,
        },
      )
    end
  end

  private

  def context_region
    hide_explore? ? :trending : :explore
  end

  def hide_explore?
    GitHub.multi_tenant_enterprise?
  end

  def trending_depreciation_enabled?
    GitHub.flipper[:trending_deprecation].enabled?(current_user)
  end

  def preload_repo_associations(repositories)
    GitHub::PrefillAssociations.prefill_associations(repositories, [
      :mirror,
      :primary_language,
      { owner: :sponsors_listing }
    ])
  end

  def preload_developer_associations(developers)
    users = developers.map(&:original_user)

    if GitHub.sponsors_enabled?
      promises = users.map do |user|
        Promise.all([
          user.async_sponsored_by_viewer?(current_user),
          user.async_sponsorable_by?(current_user),
        ])
      end
      Promise.all(promises).sync
    end

    GitHub::PrefillAssociations.prefill_associations(users, :profile)
    if logged_in?
      GitHub::PrefillAssociations.prefill_batch_method(users, :followed_by?, current_user)
    end
  end

  memoize def language
    # Maintain backwards compatibility with params[:l]
    (params[:language] || params.delete(:l)).try(:downcase)
  end

  def spoken_language_code
    params.fetch(:spoken_language_code, current_user&.profile_spoken_language_preference_code)
  end

  def since
    s = params[:since].try(:downcase)
    date_options.keys.include?(s) ? s : "daily"
  end

  def sponsorable_only?
    params[:sponsorable] == "1" && GitHub.sponsors_enabled?
  end

  def popular_repositories
    Trending.repos(viewer: current_user,
                   cache_key: cache_key_for_query("repositories"),
                   ttl: 3.hours,
                   options: trending_query_options)
  end

  def popular_developers
    results = GitHub.cache.fetch(cache_key_for_query("developer_ids"), ttl: 3.hours) do
      Trending.users(trending_query_options).map { |user, data| [user.id, data] }
    end

    users = User.where(id: results.map { |user_id, _| user_id })
    unless language
      users = users.includes(:most_popular_public_repository)
    end
    users = users.index_by(&:id)

    results.map { |user_id, data| [users[user_id], data] }
  end

  def trending_query_options
    {
      language: language,
      period: since,
      skip_min: GitHub.enterprise? || Rails.env.development?,
    }
  end

  def cache_key_for_query(type)
    if unknown_language?
      default_alias = "unknown"
    else
      default_alias = selected_language.default_alias if known_language?
    end
    "popular#{type}:#{default_alias}#{since}"
  end

  def ensure_not_multitenant_enterprise
    render_404 if hide_explore?
  end
end
