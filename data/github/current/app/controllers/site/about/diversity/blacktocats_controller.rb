# typed: true
# frozen_string_literal: true

class Site::About::Diversity::BlacktocatsController < Site::About::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :enable_fullstory, only: [:index]
  before_action :add_fullstory_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com"],
    media_src: [
      # Temporary solution for hosting an MP3 on the Blacktocats page.
      # This was initially used for the ReadMe Podcast, hence the name.
      # The ReadMe podcast has since moved onto Contentful.
      # See https://github.com/github/readme-podcast/tree/main/assets/other.
      "https://readme-podcast.github.com"
    ],
  }

  stylesheet_bundle "marketing-about-diversity"

  def index
    render "site/about/diversity/communities/blacktocats/index"
  end
end
