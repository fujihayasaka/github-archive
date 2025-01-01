# typed: false
# frozen_string_literal: true

# Class ExploreController: This is the controller for all things /explore
class ExploreController < ApplicationController
  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Repositories,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IssuesPullRequests,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Spokes

  depends_on_clusters ApplicationRecord::Copilot, optional: true

  YOUTUBE_IMAGE_THUMBNAIL_HOST = "img.youtube.com"
  USER_SUMMARY_TOPIC_STARS_LIMIT = 5

  before_action :add_csp_exceptions
  before_action :ensure_not_multitenant_enterprise

  # :site bundle dependency should be transitioned to only :explore
  stylesheet_bundle :site
  stylesheet_bundle :explore

  CSP_EXCEPTIONS = {
    img_src: [
      YOUTUBE_IMAGE_THUMBNAIL_HOST,
      ExploreFeed::Event::FEED_URL,
    ],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url],
    frame_src: ["https://www.youtube.com"],
  }

  # CAP Bypass is fine because of :ensure_not_multitenant_enterprise
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction

  include ExploreHelper
  include Trending::FeedHelper

  def index
    context_region_preset :explore

    if GitHub.enterprise?
      @sections = []
      @trending = get_trending_records

      setup_stars_section
      @subscription = newsletter_subscription if logged_in?

      # sort the sections by the sort object
      @sections = @sections.sort { |a, b| a[:sort] <=> b[:sort] }

      render "explore/index"
    else
      marketplace_listings = Marketplace::Listing.verified_and_shuffled
      featured_collection = ExploreCollection.featured_and_shuffled(limit: 1).first
      spotlights = ExploreFeed::Spotlight.all.current.to_a.shuffle
      featured_event = ExploreFeed::Event.all.upcoming_or_current.sample

      if logged_in?
        all_topics = ExploreFeed::Recommendation::Topic.all(for_user: current_user)
        non_spotlight_topics = all_topics.non_spotlight
        featured_topic = all_topics.spotlight
      else
        featured_topic = Topic.not_flagged.curated.with_logo.featured_and_shuffled.first
      end

      preload_repo_associations
      preload_developer_associations

      render "explore/feed/index", locals: {
        featured_collection: featured_collection,
        featured_event: featured_event,
        featured_topic: featured_topic,
        marketplace_listings: marketplace_listings,
        non_spotlight_topics: non_spotlight_topics,
        repository_recommendations: repository_recommendations,
        spotlights: spotlights,
        trending_repositories: trending_repositories,
        trending_developers: trending_developers,
      }
    end
  end

  private

  def ensure_not_multitenant_enterprise
    render_404 if GitHub.multi_tenant_enterprise?
  end

  # When logged in:
  #   - Only recommended repos are shown as full repository cards
  #   - Trending repos are shown with small treatment in sidebar
  #     (no star button, no images, no topics, no issue/pr/discussion tabs)
  # When logged out:
  #   - No recommended repos
  #   - Trending repos are shown as full repository cards
  def preload_repo_associations
    repos_rendered_as_cards = if logged_in?
      repository_recommendation_repositories
    else
      trending_repositories.to_a
    end

    Configurable.preload_configuration(repos_rendered_as_cards)
    GitHub::PrefillAssociations.prefill_associations(repos_rendered_as_cards, [:open_graph_image, :topics])

    if logged_in?
      GitHub::PrefillAssociations.prefill_batch_method(repos_rendered_as_cards, :starred_by?, current_user)
    end
  end

  memoize def trending_developers
    ExploreFeed::Trending::Developer.all.limit(4)
  end

  def preload_developer_associations
    users = trending_developers.map(&:original_user)
    GitHub::PrefillAssociations.prefill_associations(users, :profile)
  end

  def repository_recommendation_repositories # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @repository_recommendation_repositories ||= repository_recommendations.map(&:repository)
  end

  def repository_recommendations
    return if GitHub.enterprise?

    @repository_recommendations ||= if logged_in?
      RepositoryRecommendation.filtered_for(current_user, per_page: 10) || []
    else
      []
    end
  end

  def trending_repositories
    return if GitHub.enterprise?

    @trending_repositories ||= if logged_in?
      # Logged-in users only see 4 trending repos
      ExploreFeed::Trending::Repository.all(
        spoken_language_code: current_user.profile_spoken_language_preference_code
      ).limit(4)
    else
      ExploreFeed::Trending::Repository.all
    end
  end

  # Return the attached user to a valid unsubscribe token
  def user_from_token
    token = NewsletterSubscription.validate_token(params[:token].to_s)
    token.try(:user)
  end

  def newsletter_subscription
    NewsletterSubscription.where("user_id = ? AND name = ?", current_user.id, "explore").first
  end

  def setup_stars_section
    if logged_in?
      @stars = explore_follow_stars_repositories(
        @trending.map { |r| r[0].id },
      )
      if @stars.present?
        @sections.push(
          id: "explore-stars",
          component: Explore::StarsComponent,
          args: { stars: @stars, explore_period: explore_period },
          sort: 1,
        )
      end
    else
      @sections.push(
        id: "explore-stars",
        component: Explore::StarsComponent,
        args: { stars: [], explore_period: explore_period },
      )
    end
  end

  def get_trending_records
    if GitHub.munger_available?
      ExploreFeed::Trending::Repository.all(period: explore_period)
    else
      []
    end
  end

  def explore_follow_stars_repositories(exclude_repos)
    GitHub.dogstats.distribution_time("explore.stars", tags: ["action:follow", "period:#{explore_period}"]) do
      Star.from_following(
        current_user,
        period: explore_period,
        limit: 6,
        exclude_repos: exclude_repos,
        include_topics: false
      )
    end
  end

  # normalize since, in case there's weird things passed in
  def explore_period # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    @since ||=
      case params[:since]
      when "daily"
        "daily"
      when "monthly"
        "monthly"
      else
        "weekly"
      end
  end
  helper_method :explore_period

  def parsed_issues_query
    [[:is, "open"], [:is, "issue"]]
  end
  helper_method :parsed_issues_query
end
