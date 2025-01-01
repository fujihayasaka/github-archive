# typed: true
# frozen_string_literal: true

class Site::GlobeController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :allow_custom_globe_server_url, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url],
    connect_src: [GitHub.asset_host_url],
  }

  javascript_bundle "webgl-globe", only: :index, unless: -> { helpers.local_globe_server_enabled? }
  javascript_bundle :"home-globe", only: :index
  stylesheet_bundle :"home-globe", only: :index

  def index
    render "site/globe/index"
  end

  private

  def allow_custom_globe_server_url
    if Rails.env.development? && ENV["GLOBE_SERVER_URL"].present?
      csp_exceptions = {
        script_src: [ENV["GLOBE_SERVER_URL"]],
      }

      SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
    end
  end
end
