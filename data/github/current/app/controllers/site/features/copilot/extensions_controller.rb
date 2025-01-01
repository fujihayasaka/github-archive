# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::ExtensionsController < Site::Features::BaseController

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  javascript_bundle "marketing-copilot-extensions-hero"
  stylesheet_bundle "landing-pages"                      # Includes Primer Brand
  stylesheet_bundle "feature-shared-fp24"                # Shared with other /features pages
  stylesheet_bundle "feature-copilot-extensions"         # Only for this page
  stylesheet_bundle "feature-copilot-extensions-hero-ui" # Only for this page
  javascript_bundle "marketing-copilot-extensions-cta"

  def index
    render_react_app(
      title: "GitHub Copilot Extensions · Your favorite tools have entered Copilot Chat.",
      page_data: {
        class: "header-overlay",
        marketing_page_theme: "dark",
        richweb: {
          title: "GitHub Copilot Extensions · Your favorite tools have entered Copilot Chat.",
          description: "Extend GitHub Copilot with ready-to-use extensions or build your own using our developer platform with APIs, documentation, and guides.",
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/copilot-extensions.png"),
        },
      },
      ssr: true
    )
  end
end
