# typed: true
# frozen_string_literal: true

class Site::Features::CodespacesController < Site::Features::BaseController
  extend T::Sig

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # Add features subnav
  layout -> {
    T.bind(self, Site::Features::CodespacesController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "feature-codespaces", only: [:index], unless: -> do
    T.bind(self, Site::Features::CodespacesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::CodespacesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodespacesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-codespaces-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodespacesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
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
        }
      )
    else
      render "site/features/codespaces/index"
    end
  end
end
