# typed: true
# frozen_string_literal: true

class Site::Features::DiscussionsController < Site::Features::BaseController
  extend T::Sig

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
  layout -> {
    T.bind(self, Site::Features::DiscussionsController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "feature-discussions", only: [:index], unless: -> do
    T.bind(self, Site::Features::DiscussionsController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::DiscussionsController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::DiscussionsController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-discussions-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::DiscussionsController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      page_meta = {
        title: "GitHub Discussions · Developer Collaboration & Communication Tool ·  GitHub",
        description: "Learn about GitHub Discussions, a collaboration tool & forum connecting the developer community. Collaborate on code, ask questions, share ideas, & build connections"
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
            image: image_path("modules/site/social-cards/discussions-social.jpg"),
          },
        }
      )
    else
      render "site/features/discussions/index"
    end
  end
end
