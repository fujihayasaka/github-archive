# typed: true
# frozen_string_literal: true

class Site::HomeController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]
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

  stylesheet_bundle :"landing-pages", :home, only: [:index]
  javascript_bundle :"marketing-essentials", only: [:index]

  def index
    title = "GitHub · Build and ship software on a single, collaborative platform"
    header_classes = feature_enabled_globally_or_for_current_user?(:site_homepage_fixed_header) ? "header-overlay header-overlay-fixed js-header-overlay-fixed" : "header-overlay"

    render_react_app(
      app_name: "landing-pages",
      title: title,
      page_data: {
        class: header_classes,
        marketing_page_theme: "dark",
        richweb: {
          title: title,
          description: _("Join the world's most widely adopted AI-powered developer platform where millions of developers, businesses, and the largest open source community build software that advances humanity."),
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/home24.jpg"),
        },
      },
      payload: {
        isLoggedIn: logged_in?,
      },
      ssr: true,
    )
  end
end
