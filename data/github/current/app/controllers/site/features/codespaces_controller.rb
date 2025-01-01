# typed: true
# frozen_string_literal: true

class Site::Features::CodespacesController < Site::Features::BaseController

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # Add features subnav
  layout "site_features"

  stylesheet_bundle "landing-pages", "feature-shared-fp24", "feature-codespaces", only: [:index]

  def index
    page_meta = {
      title: "GitHub Codespaces",
      description: "GitHub Codespaces gets you up and coding faster with fully configured, secure cloud development environments native to GitHub."
    }

    render_react_app(
      title: page_meta[:title],
      page_data: {
        class: "header-overlay",
        marketing_page_theme: "dark",
        richweb: {
          title: page_meta[:title],
          description: page_meta[:description],
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/codespaces-ga-individuals.jpg"),
        },
        revenue_play: "Platform",
      }
    )
  end
end
