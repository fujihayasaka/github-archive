# typed: true
# frozen_string_literal: true

class Site::Features::CodeSearchController < Site::Features::BaseController

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # Add features subnav
  layout -> {
    T.bind(self, Site::Features::CodeSearchController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "feature-codesearch", only: [:index], unless: -> do
    T.bind(self, Site::Features::CodeSearchController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeSearchController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeSearchController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-code-search-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeSearchController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
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
        }
      )
    else
      render "site/features/code_search/index"
    end
  end
end
