# typed: true
# frozen_string_literal: true

class Site::About::Diversity::CommunitiesController < Site::About::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :enable_fullstory, only: [:index]
  before_action :add_fullstory_csp_exceptions, only: [:index]


  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com"],
  }

  stylesheet_bundle "marketing-about-diversity"

  def index
    render "site/about/diversity/communities/index"
  end
end
