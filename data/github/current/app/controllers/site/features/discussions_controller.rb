# typed: true
# frozen_string_literal: true

class Site::Features::DiscussionsController < Site::Features::BaseController

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    media_src: [GitHub.asset_host_url]
  }

  # Add features subnav
  layout "site_features"

  # New styles
  stylesheet_bundle "landing-pages", "feature-shared-fp24", "feature-discussions", only: [:index]

  def index
    page_meta = {
      title: "GitHub Discussions · Developer Collaboration & Communication Tool",
      description: "Learn about GitHub Discussions, a collaboration tool & forum connecting the developer community. Collaborate on code, ask questions, share ideas, & build connections"
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
          image: image_path("modules/site/social-cards/discussions-social.jpg"),
        },
      }
    )
  end
end
