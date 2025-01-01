# typed: true
# frozen_string_literal: true

class Site::HomeController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :allow_custom_globe_server_url, only: :index
  before_action :enable_fullstory, only: :index
  before_action :add_fullstory_csp_exceptions, only: :index

  around_action :switch_locale, only: :index

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
    frame_src: ["https://www.youtube-nocookie.com"],
    media_src: [GitHub.asset_host_url],
    connect_src: [GitHub.asset_host_url],
  }

  stylesheet_bundle :experiments, only: [:index], unless: :logged_in?

  javascript_bundle :home, unless: :logged_in?
  javascript_bundle "marketing-experiments", only: [:index]
  javascript_bundle "webgl-globe", only: :index, unless: -> { helpers.local_globe_server_enabled? }

  def index
    render "site/home/index", locals: { globe_enabled: feature_enabled_globally_or_for_current_user?(:home_page_globe) }
  end

  private

  def allow_custom_globe_server_url
    if Rails.env.development? && ENV["GLOBE_SERVER_URL"].present?
      csp_exceptions = {
        script_src: [ENV["GLOBE_SERVER_URL"]]
      }

      SecureHeaders.append_content_security_policy_directives(request, csp_exceptions)
    end
  end
end
