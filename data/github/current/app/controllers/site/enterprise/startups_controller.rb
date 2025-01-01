# typed: true
# frozen_string_literal: true

class Site::Enterprise::StartupsController < Site::Enterprise::BaseController
  before_action :add_csp_exceptions, only: [:index, :partners, :acceptance]

  CSP_EXCEPTIONS = {
    form_action: %w( https://s88570519.t.eloqua.com/e/f2 ),
    media_src: [GitHub.asset_host_url]
  }

  javascript_bundle "marketing-startups"
  javascript_bundle "marketing-form-validator"
  stylesheet_bundle "marketing-startups"

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index, :partners]

  depends_on_clusters ApplicationRecord::Mysql5, only: [:partners], optional: true

  def index
    render "site/enterprise/startups/index"
  end

  def thanks # rubocop:todo GitHub/UseRestfulActions
    render "site/enterprise/startups/thanks"
  end

  def acceptance # rubocop:todo GitHub/UseRestfulActions
    render "site/enterprise/startups/acceptance"
  end

  def partners # rubocop:todo GitHub/UseRestfulActions
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::Startups::Pages::Partners)
    partners_page_data = Site::Contentful::Marketing::Startups::Pages::Partners.new.view_data

    render "site/contentful/enterprise/startups/partners", locals: {
      page: partners_page_data[:page_data],
      partners: partners_page_data[:partners]
    }
  end
end
