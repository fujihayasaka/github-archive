# typed: true
# frozen_string_literal: true

module Site::CustomerStories
  class SearchController < BaseController
    include StoryFilteringAndPagination

    before_action :marketing_turbo_enable

    depends_on_clusters ApplicationRecord::Mysql1

    def index
      stories = Site::Contentful::CustomerStories::CustomerStory.query(
        limit: Site::Contentful::CustomerStories::Pages::CategoryPage::NUMBER_OF_STORIES_PER_PAGE,
        skip: params[:offset] || 0,
        select: Site::Contentful::CustomerStories::CustomerStory.sparse_fields_for_index,
        fields: normalized_filter_params
      )

      respond_to do |format|
        format.turbo_stream do
          render "site/contentful/customer_stories/search/index",
            locals: { stories: stories, category: params[:category], offset: next_offset, target: params[:target], filter_params: filter_params },
            layout: false
        end
      end
    end

    helper_method :show_load_more_button?

    private

    def allowed_filters
      %i[category industry region feature size]
    end
  end
end
