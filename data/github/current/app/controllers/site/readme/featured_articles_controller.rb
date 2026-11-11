# typed: true
# frozen_string_literal: true

class Site::Readme::FeaturedArticlesController < Site::Readme::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:show],
    optional: true

  def index
    category = Site::Contentful::Readme::FeaturedArticle.category

    if category.present?
      render "site/readme/categories/show", locals: {
        category: category,
        story_class: Site::Contentful::Readme::FeaturedArticle
      }
    else
      render_404
    end
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage, story_slug: params[:id], for_readme_staff: readme_staff?)

    page_data = Site::Contentful::Readme::Pages::FeaturedArticles::ShowPage.new(story_slug: params[:id], for_readme_staff: readme_staff?).view_data

    render_404 and return if page_data[:story].blank?

    # Ensure story klass is available for fetching the body
    page_data[:story][:klass] = "Site::Contentful::Readme::FeaturedArticle"

    render "site/readme/featured_articles/show", locals: { page_data: page_data }
  end
end
