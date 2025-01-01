# typed: true
# frozen_string_literal: true

class Site::FeaturesController < Site::Features::BaseController

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  layout "layouts/site_features"

  stylesheet_bundle "landing-pages", "feature-shared-fp24", "features-fp24"

  def index
    return Site::LandingPagesController.dispatch(:show, request, response) if feature_enabled_globally_or_for_current_user?(:contentful_lp_flex_features)

    page_meta = {
      title: "GitHub Features",
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
      },
    )
  end
end
