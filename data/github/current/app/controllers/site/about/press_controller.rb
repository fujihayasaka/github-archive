# typed: true
# frozen_string_literal: true

class Site::About::PressController < Site::About::BaseController
  before_action :enable_fullstory
  before_action :add_fullstory_csp_exceptions

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  def index
    page = params.fetch(:page, 1).to_i

    respond_to do |format|
      format.html do
        press_page_data = Site::Contentful::Marketing::Press::Pages::IndexPage.new(page: page).view_data

        paginated_articles = WillPaginate::Collection.create(page, Site::Contentful::Marketing::Press::Pages::IndexPage::PER_PAGE_LIMIT, press_page_data[:total_number_of_articles]) do |group|
          group.replace(press_page_data[:articles])
        end

        render "site/about/press/index", locals: {
          page: press_page_data[:page_data],
          articles: paginated_articles,
          render_pagination: paginated_articles.total_pages > 1,
        }
      end

      format.json do
        articles = Rails.cache.fetch("press-feed-json", expires_in: 5.minutes) do
          Site::Contentful::Marketing::Press::Article.where(limit: 25).map(&:feed_json)
        end

        if stale?(etag: articles, last_modified: articles.first[:date])
          json_feed = {
            version: "https://jsonfeed.org/version/1",
            title: "GitHub Press",
            feed_url: "https://github.com/about/press.json",
            expired: false,
            items: articles
          }

          render json: json_feed
        end
      end
    end
  end
end
