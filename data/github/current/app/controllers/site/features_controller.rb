# typed: true
# frozen_string_literal: true

class Site::FeaturesController < Site::Features::BaseController
  extend T::Sig

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  # Add features subnav
  layout -> {
    T.bind(self, Site::FeaturesController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "features", only: [:index], unless: -> do
    T.bind(self, Site::FeaturesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::FeaturesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::FeaturesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "features-fp24", only: [:index], if: -> do
    T.bind(self, Site::FeaturesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      page_meta = {
        title: "Features | GitHub",
        description: "Get the right tools for the job. Automate your CI/CD and DevOps workflow with GitHub Actions, build securely, manage teams and projects, and review code in one place."
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
            image: image_path("modules/site/social-cards/features-launchpad.png"),
          },
        }
      )
    else
      render "site/features/index"
    end
  end
end
