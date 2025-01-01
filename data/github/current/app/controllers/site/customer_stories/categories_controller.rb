# typed: true
# frozen_string_literal: true

module Site::CustomerStories
  class CategoriesController < BaseController
    include StoryFilteringAndPagination

    before_action :add_csp_exceptions
    before_action :marketing_turbo_enable

    depends_on_clusters ApplicationRecord::Mysql1, # Feature flag lookup
      # Clusters used for logged in nav
      ApplicationRecord::Mysql2,
      ApplicationRecord::Collab,
      ApplicationRecord::IamAbilities,
      ApplicationRecord::NotificationsEntries,
      ApplicationRecord::Repositories

    depends_on_clusters ApplicationRecord::Mysql5,
      optional: true

    CSP_EXCEPTIONS = { img_src: [GitHub.contentful_customer_stories_image_host_url], media_src: [ExploreFeed::CustomerStory::CUSTOMER_STORIES_FEED_URL] }.freeze

    def show
      RevalidatePageJob.perform_later(Site::Contentful::CustomerStories::Pages::CategoryPage, category_id: params[:category], for_staff: customer_stories_staff?)

      data = Site::Contentful::CustomerStories::Pages::CategoryPage.new(**T.unsafe({
        category_id: params[:category],
        for_staff: customer_stories_staff?,
        **normalized_filter_params
      })).view_data

      render_404 and return if data[:page_data].nil?

      render "site/contentful/customer_stories/categories/show", locals: {
        page_data: data[:page_data],
        stories: data[:stories],
        total_stories: data[:total_stories],
        filter_params: filter_params,
        next_offset: next_offset
      }
    end

    helper_method :show_load_more_button?

    private

    def allowed_filters
      %i[industry region feature size]
    end
  end
end
