# typed: true
# frozen_string_literal: true

class Site::Features::ActionsController < Site::Features::BaseController


  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Repositories,
    only: [:index]

  # Add features subnav
  layout "site_features"
  # New styles
  stylesheet_bundle "landing-pages", "feature-shared-fp24", "feature-actions"

  def index
    page_meta = {
      title: "GitHub Actions",
      description: "Easily build, package, release, update, and deploy your project in any language—on GitHub or any external system—without having to run code yourself."
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
          image: image_path("modules/site/social-cards/actions.png"),
        },
        revenue_play: "Platform",
      }
    )
  end
end
