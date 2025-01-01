# typed: true
# frozen_string_literal: true

class Site::Features::CodeReviewController < Site::Features::BaseController
  extend T::Sig

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1, only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com"]
  }

  # Add features subnav
  layout -> {
    T.bind(self, Site::Features::CodeReviewController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "site-legacy", only: [:index], unless: -> do
    T.bind(self, Site::Features::CodeReviewController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeReviewController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeReviewController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-code-review-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::CodeReviewController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      page_meta = {
        title: "Features · Code review",
        description: "Make code review seamless with GitHub. Request reviews, propose changes, keep track of versions, and protect branches on the path to better code with your team."
      }

      render_react_app(
        title: page_meta[:title],
        page_data: {
          class: "header-overlay",
          marketing_page_theme: "light",
          richweb: {
            title: page_meta[:title],
            description: page_meta[:description],
            url: T.must(request).original_url,
            image: image_path("modules/site/social-cards/features.png"),
          },
        }
      )
    else
      render "site/features/code_review/index"
    end
  end
end
