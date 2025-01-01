# typed: true
# frozen_string_literal: true

class Site::Features::CodeSearchController < Site::Features::BaseController


  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # Add features subnav
  layout "site_features"

  stylesheet_bundle "landing-pages", "feature-shared-fp24", "feature-code-search", only: [:index]

  def index
    page_meta = {
      title: "GitHub Code Search",
      description: "With GitHub code search, your code—and the world’s—is at your fingertips."
    }

    render_react_app(
      title: page_meta[:title],
      page_data: {
        class: "header-dark",
        marketing_page_theme: "light",
        richweb: {
          title: page_meta[:title],
          description: page_meta[:description],
          url: T.must(request).original_url,
          image: image_path("modules/site/social-cards/code-search-beta.png"),
        },
        revenue_play: "Platform",
      }
    )
  end
end
