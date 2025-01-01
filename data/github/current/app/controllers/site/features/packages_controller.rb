# typed: true
# frozen_string_literal: true

class Site::Features::PackagesController < Site::Features::BaseController
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
    T.bind(self, Site::Features::PackagesController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old JS
  javascript_bundle "marketing-packages", only: [:index], unless: -> do
    T.bind(self, Site::Features::PackagesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # Old styles
  stylesheet_bundle "feature-packages", only: [:index], unless: -> do
    T.bind(self, Site::Features::PackagesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::PackagesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::PackagesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-packages-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::PackagesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      page_meta = {
        title: "GitHub Packages: Your packages, at home with their code",
        description: "With GitHub Packages you can safely publish and consume packages within your organization or with the entire world."
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
            image: image_path("modules/site/social-cards/package-registry.png"),
          },
        }
      )
    else
      render "site/features/packages/index"
    end
  end
end
