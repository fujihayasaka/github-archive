# typed: true
# frozen_string_literal: true

class Site::Readme::TopicsController < Site::Readme::BaseController
  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index, :show]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index, :show],
    optional: true

  def index
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::IndexPage, for_readme_staff: readme_staff?)

    render "site/readme/topics/index", locals: {
      page_data: Site::Contentful::Readme::Pages::Topics::IndexPage.new(for_readme_staff: readme_staff?).view_data
    }
  end

  def show
    RevalidatePageJob.perform_later(Site::Contentful::Readme::Pages::Topics::ShowPage, topic_slug: params[:id], for_readme_staff: readme_staff?)

    page_data = Site::Contentful::Readme::Pages::Topics::ShowPage.new(topic_slug: params[:id], for_readme_staff: readme_staff?).view_data

    if page_data[:topic].present?
      render "site/readme/topics/show", locals: { page_data: page_data }
    else
      render_404
    end
  end
end
