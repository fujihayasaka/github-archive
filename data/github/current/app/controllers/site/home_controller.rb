# typed: true
# frozen_string_literal: true

class Site::HomeController < Site::BaseController
  before_action :add_csp_exceptions, only: [:index]
  before_action :localized_alternative_links, only: [:index]

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
    img_src: [GitHub.asset_host_url, GitHub.og_image_generator_base_url, GitHub.contentful_marketing_image_host_url],
    media_src: [GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url, GitHub.contentful_marketing_video_host_url],
    connect_src: [GitHub.asset_host_url],
  }

  stylesheet_bundle :"landing-pages", :home, only: [:index]
  javascript_bundle :"marketing-essentials", only: [:index]

  def index
    header_classes = FeatureFlag.vexi.enabled?(:site_homepage_fixed_header, current_user, default: false) ? "header-overlay header-overlay-fixed js-header-overlay-fixed" : "header-overlay"

    options = {
      slug: request&.path,
      preview: fetch_contentful_preview?
    }
    options[:locale] = I18n.locale if user_defined_locale_enabled?

    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, **options) unless fetch_contentful_preview?
    contentful_page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(**options).view_data

    if contentful_page_data.present? && FeatureFlag.vexi.enabled?(:site_homepage_contentful, current_user, default: false)
      render_react_app(
        app_name: "landing-pages",
        title: contentful_page_data[:title],
        path_override: "/home",
        page_data: {
          class: header_classes,
          marketing_page_theme: "dark",
          description: contentful_page_data[:seo].try(:dig, :description),
          richweb: {
            description: contentful_page_data[:seo].try(:dig, :description),
            image: contentful_page_data[:seo].try(:dig, :social_media_image),
            title: contentful_page_data[:title],
            url: T.must(request).original_url
          },
          revenue_play: contentful_page_data.fetch(:revenue_play, "Platform"),
        },
        payload: {
          contentfulRawJsonResponse: contentful_page_data[:contentful_raw_json_response],
          isLoggedIn: logged_in?,
          hasOrganization: current_user&.organizations&.any?,
        },
      )
    else
      title = "GitHub · Build and ship software on a single, collaborative platform"

      render_react_app(
        app_name: "landing-pages",
        title: title,
        path_override: "/home",
        page_data: {
          class: header_classes,
          marketing_page_theme: "dark",
          richweb: {
            title: title,
            description: _("Join the world's most widely adopted, AI-powered developer platform where millions of developers, businesses, and the largest open source community build software that advances humanity."),
            url: T.must(request).original_url,
            image: image_path("modules/site/social-cards/home24.jpg"),
          },
          revenue_play: "Platform",
        },
        payload: {
          isLoggedIn: logged_in?,
          hasOrganization: current_user&.organizations&.any?,
        }
      )
    end
  end
end
