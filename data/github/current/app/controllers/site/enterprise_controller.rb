# typed: true
# frozen_string_literal: true

class Site::EnterpriseController < Site::Enterprise::BaseController
  extend T::Sig

  before_action :add_csp_exceptions, only: [:index]

  include ReactHelper
  include StaticAssetHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

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

  stylesheet_bundle "enterprise", only: [:index], if: -> do
    T.bind(self, Site::EnterpriseController)
    feature_enabled_globally_or_for_current_user?(:enterprise_show_prototype)
  end

  stylesheet_bundle "landing-pages", only: [:index], unless: -> do
    T.bind(self, Site::EnterpriseController)
    feature_enabled_globally_or_for_current_user?(:enterprise_show_prototype)
  end

  stylesheet_bundle "enterprise-react", only: [:index], unless: -> do
    T.bind(self, Site::EnterpriseController)
    feature_enabled_globally_or_for_current_user?(:enterprise_show_prototype)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:enterprise_show_prototype)
      render "site/enterprise/index"
    else
      eyebrow_banner_data = {
        render: feature_enabled_globally_or_for_current_user?(:site_enterprise_galaxy_eyebrow_banner),
        title: "GitHub Galaxy: A global enterprise event tour",
        subtitle: "Register now to join us in a city near you.",
        icon: image_path("modules/site/galaxy/eyebrow-galaxy-24@2x.png"),
        analytics: analytics_click_attributes(**analytics_tags_from_content(analytics: { category: "Eyebrow Banner", action: "click", ref_loc: "hero" }, text: "GitHub Galaxy: A global enterprise event tour")),
        url: "https://galaxy.github.com/?ref_cta=Galaxy24+Eyebrow+Banner&ref_loc=hero&ref_page=%2Fenterprise&utm_medium=entWeb&utm_source=github&utm_campaign=2024q3-em-Galaxy24",
      }

      if feature_enabled_globally_or_for_current_user?(:site_enterprise_galaxy_eyebrow_banner_virtual_event)
        eyebrow_banner_data[:url] = "https://galaxy.github.com/virtual?utm_source=github&utm_medium=site-banner&utm_campaign=2024q4-evt-ww-GitHub-Galaxy-Virtual"
        eyebrow_banner_data[:analytics] = analytics_click_attributes(**analytics_tags_from_content(analytics: { category: "Eyebrow Banner", action: "click", ref_loc: "hero" }, text: "GitHub Galaxy: Register now for our virtual enterprise event"))
        eyebrow_banner_data[:title] = "GitHub Galaxy: Register now for our virtual enterprise event"
        eyebrow_banner_data[:subtitle] = "Explore our vision for AI-powered software development."
      end

      render_react_app(
        title: "The AI Powered Developer Platform.",
        page_data: {
          class: "header-overlay",
          marketing_page_theme: "dark",
          richweb: {
            title: "The AI Powered Developer Platform.",
            description: "Whether you’re working solo or leading an enterprise, GitHub has everything you need to build and scale your team’s workflow. Choose the plan that’s right for your hosting environment and security policies, and we’ll get you set up in no time.",
            url: T.must(request).original_url,
            image: image_path("modules/site/social-cards/enterprise-2023.png"),
          }
        },
        payload: {
          heroLgMovUrl: static_asset_path("/images/modules/site/enterprise/2023/hero-lg.mp4"),
          heroSmMovUrl: static_asset_path("/images/modules/site/enterprise/2023/hero-sm.mp4"),
          siteSecurityReactEnabled: feature_enabled_globally_or_for_current_user?(:site_security_react),
          eyebrowBannerData: eyebrow_banner_data
        },
        ssr: true
      )
    end
  end
end
