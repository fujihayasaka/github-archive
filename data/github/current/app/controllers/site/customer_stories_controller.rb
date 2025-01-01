# typed: true
# frozen_string_literal: true

class Site::CustomerStoriesController < Site::CustomerStories::BaseController
  before_action :add_csp_exceptions
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1, # Feature flag lookup
    # Clusters used for logged in nav
    ApplicationRecord::Mysql2,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories

  depends_on_clusters ApplicationRecord::Mysql5,
    optional: true

  CSP_EXCEPTIONS = { img_src: [GitHub.contentful_customer_stories_image_host_url] }.freeze

  def index
    page = Site::Contentful::CustomerStories::Pages::IndexPage.new(for_staff: customer_stories_staff?, cache_version:)

    if enable_fragment_caching?
      page.revalidate_if_stale
    else
      RevalidatePageJob.perform_later(Site::Contentful::CustomerStories::Pages::IndexPage, for_staff: customer_stories_staff?, cache_version:)
    end

    page_data = page.view_data
    homepage = page_data[:homepage]
    enterprise_stories = page_data[:enterprise_stories]
    team_stories = page_data[:team_stories]

    render "site/contentful/customer_stories/index", locals: {
      page_data: homepage,
      enterprise_stories: enterprise_stories,
      team_stories: team_stories,
      page: page,
    }
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage, story_slug: params[:id], for_staff: customer_stories_staff?)

    page_data = Site::Contentful::CustomerStories::Pages::CustomerStoryShowPage.new(story_slug: params[:id], for_staff: customer_stories_staff?).view_data

    if page_data[:customer_story].present?
      render "site/contentful/customer_stories/show", locals: { customer_story: page_data[:customer_story] }
    else
      render_404
    end
  end

  private def cache_version
    enable_fragment_caching? ? :v2 : :v1
  end

  private def enable_fragment_caching?
    feature_enabled_globally_or_for_current_user?(:customer_stories_fragment_caching)
  end
  helper_method :enable_fragment_caching?
end
