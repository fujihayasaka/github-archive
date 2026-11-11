# typed: true
# frozen_string_literal: true

class Site::Contentful::Marketing::Press::Pages::IndexPage
  PER_PAGE_LIMIT = 18.freeze

  def initialize(page:)
    @page = page
  end

  def view_data
    fetch_data_from_contentful
  end

  def fetch_data_from_contentful
    page_data = Site::Contentful::Marketing::Page.find("about-press")

    articles = Site::Contentful::Marketing::Press::Article.where(limit: PER_PAGE_LIMIT, offset: (@page - 1) * PER_PAGE_LIMIT)

    {
      articles: articles,
      page_data: page_data,
      total_number_of_articles: articles.total
    }
  end
end
