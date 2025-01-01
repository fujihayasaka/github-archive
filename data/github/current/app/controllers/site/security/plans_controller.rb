# typed: true
# frozen_string_literal: true

class Site::Security::PlansController < Site::BaseController

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  stylesheet_bundle "landing-pages"

  def index
    if feature_enabled_globally_or_for_current_user?(:site_security_plans)
      title = "GitHub Advanced Security · Built-in protection for every repository"
      header_classes = "header-overlay header-overlay-fixed js-header-overlay-fixed"

      render_react_app(
        app_name: "landing-pages",
        title: title,
        page_data: {
          class: header_classes,
          marketing_page_theme: "dark",
          richweb: {
            title: title,
            description: "Fix vulnerabilities and safeguard your software supply chain with built-in, AI-powered security.",
            url: T.must(request).original_url,
            # TODO: Update unfurl image asset
            image: image_path("modules/site/social-cards/copilot-extensions.png"),
          },
          revenue_play: "Security",
        },
      )
    else
      render_404
    end
  end
end
