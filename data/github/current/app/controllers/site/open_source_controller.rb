# typed: true
# frozen_string_literal: true

class Site::OpenSourceController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql5,
    only: [:index],
    optional: true

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_readme_image_host_url, GitHub.contentful_readme_download_host_url],
    form_action: %w( https://github.us11.list-manage.com ),
    frame_src: ["https://www.youtube.com"],
  }

  stylesheet_bundle "site-legacy"

  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if FeatureFlag.vexi.enabled?(:contentful_lp_open_source, current_user, default: false)

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::OpenSource::Pages::IndexPage)
    stories = Site::Contentful::Marketing::OpenSource::Pages::IndexPage.new.view_data

    render "site/open_source/index", locals: {
      stories: stories[:stories],
    }
  end
end
