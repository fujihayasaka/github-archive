# typed: true
# frozen_string_literal: true

class Site::About::Diversity::ReportController < Site::About::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :load_contentful_page, only: [:index]
  before_action :enable_fullstory, only: [:index]
  before_action :add_fullstory_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Repositories, ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [
      # Temporary solution for hosting an MP3 file.
      # This was initially used for the ReadMe Podcast, hence the name.
      # The ReadMe podcast has since moved onto Contentful.
      # See https://github.com/github/readme-podcast/tree/main/assets/other.
      "https://readme-podcast.github.com"
    ],
  }

  stylesheet_bundle "marketing-about-diversity"

  def index
    if @contentful_page.present?
      render "site/about/diversity/report/index", locals: { page: @contentful_page }
    else
      render_404
    end
  end

  private

  def load_contentful_page
    return unless feature_enabled_globally_or_for_current_user?(:contentful_marketing_diversity_report)

    if feature_enabled_globally_or_for_current_user?(:contentful_marketing_diversity_report2024)
      @contentful_page = Site::Contentful::Marketing::Page.find("about-diversity-report-2024")
    else
      @contentful_page = Site::Contentful::Marketing::Page.find("about-diversity-report-2023")
    end
  end
end
