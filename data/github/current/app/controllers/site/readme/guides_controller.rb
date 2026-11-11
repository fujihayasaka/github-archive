# typed: true
# frozen_string_literal: true

class Site::Readme::GuidesController < Site::Readme::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:show],
    optional: true

  def index
    category = Site::Contentful::Readme::Guide.category

    if category.present?
      render "site/readme/categories/show", locals: {
        category: category,
        story_class: Site::Contentful::Readme::Guide
      }
    else
      render_404
    end
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Guides::ShowPage, story_slug: params[:id], for_readme_staff: readme_staff?)

    page_data = Site::Contentful::Readme::Pages::Guides::ShowPage.new(story_slug: params[:id], for_readme_staff: readme_staff?).view_data

    render_404 and return if page_data[:story].blank?

    # Ensure story klass is available for fetching the body
    page_data[:story][:klass] = "Site::Contentful::Readme::Guide"

    render "site/readme/guides/show", locals: { page_data: page_data }
  end
end
