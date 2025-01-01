# typed: true
# frozen_string_literal: true

class Site::EnterpriseController < Site::Enterprise::BaseController
  include StaticAssetHelper

  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  javascript_bundle "marketing-enterprise"

  stylesheet_bundle "enterprise", only: [:index], if: :enterprise_show_prototype_enabled?
  stylesheet_bundle "landing-pages", only: [:index], unless: :enterprise_show_prototype_enabled?
  stylesheet_bundle "enterprise-react", only: [:index], unless: :enterprise_show_prototype_enabled?

  def index
    if enterprise_show_prototype_enabled?
      render "site/enterprise/index"
    else
      eyebrow_banner_data = {
        render: feature_enabled_globally_or_for_current_user?(:site_galaxy25_eyebrow_banner),
        title: "GitHub Galaxy ‘25",
        subtitle: "A global enterprise tour. Register now.",
        icon: image_path("modules/site/galaxy/eyebrow-galaxy-25@2x.png"),
        analytics: analytics_click_attributes(**analytics_tags_from_content(analytics: { category: "Eyebrow Banner", action: "click", ref_loc: "hero" }, text: "GitHub Galaxy ‘25 A global enterprise tour. Register now.")),
        url: "https://galaxy.github.com/?ref_cta=Galaxy25+Eyebrow+Banner&ref_loc=hero&ref_page=%2Fenterprise&utm_medium=entWeb&utm_source=github&utm_campaign=2025q3-em-Galaxy25",
      }

      if feature_enabled_globally_or_for_current_user?(:site_enterprise_galaxy_eyebrow_banner_virtual_event)
        eyebrow_banner_data[:url] = "https://galaxy.github.com/virtual?utm_source=github&utm_medium=site-banner&utm_campaign=2025q4-evt-ww-GitHub-Galaxy-Virtual"
        eyebrow_banner_data[:analytics] = analytics_click_attributes(**analytics_tags_from_content(analytics: { category: "Eyebrow Banner", action: "click", ref_loc: "hero" }, text: "GitHub Galaxy: Register now for our virtual enterprise event"))
        eyebrow_banner_data[:title] = "GitHub Galaxy: Register now for our virtual enterprise event"
        eyebrow_banner_data[:subtitle] = "Explore our vision for AI-powered software development."
      end

      render_react_app(
        app_name: "landing-pages",
        title: "The AI Powered Developer Platform.",
        page_data: {
          class: "header-overlay",
          marketing_page_theme: "dark",
          richweb: {
            title: "The AI Powered Developer Platform.",
            description: "Whether you’re working solo or leading an enterprise, GitHub has everything you need to build and scale your team’s workflow. Choose the plan that’s right for your hosting environment and security policies, and we’ll get you set up in no time.",
            url: T.must(request).original_url,
            image: image_path("modules/site/social-cards/enterprise-2023.png"),
          },
          revenue_play: "Platform",
        },
        payload: {
          heroLgMovUrl: static_asset_path("/images/modules/site/enterprise/2023/hero-lg.mp4"),
          heroSmMovUrl: static_asset_path("/images/modules/site/enterprise/2023/hero-sm.mp4"),
          eyebrowBannerData: eyebrow_banner_data,
          contentfulRawJsonResponse: contentful_page_data,
        },
      )
    end
  end

  private

  def enterprise_show_prototype_enabled?
    feature_enabled_globally_or_for_current_user?(:enterprise_show_prototype)
  end

  def contentful_page_data
    RevalidatePageJob.perform_later(Site::Contentful::Marketing::LandingPages::Pages::ShowPage, slug: request&.path)
    page_data = Site::Contentful::Marketing::LandingPages::Pages::ShowPage.new(slug: request&.path).view_data

    page_data[:contentful_raw_json_response] if page_data.present?
  end
end
