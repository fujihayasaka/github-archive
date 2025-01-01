# typed: true
# frozen_string_literal: true

class Site::Features::IssuesController < Site::Features::BaseController
  extend T::Sig

  include ReactHelper

  sig { returns(String) }
  def self.react_bundle_name
    "landing-pages"
  end

  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    only: [:index]

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com"],
    media_src: [GitHub.asset_host_url]
  }

  # Add features subnav
  layout -> {
    T.bind(self, Site::Features::IssuesController)
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      "site_features"
    end
  }

  # Old styles
  stylesheet_bundle "feature-issues", only: [:index], unless: -> do
    T.bind(self, Site::Features::IssuesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  # New styles
  stylesheet_bundle "landing-pages", only: [:index], if: -> do
    T.bind(self, Site::Features::IssuesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-shared-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::IssuesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  stylesheet_bundle "feature-issues-fp24", only: [:index], if: -> do
    T.bind(self, Site::Features::IssuesController)
    feature_enabled_globally_or_for_current_user?(:site_fp24)
  end

  def index
    if feature_enabled_globally_or_for_current_user?(:site_fp24)
      page_meta = {
        title: "GitHub Issues · Project planning for developers",
        description: "Give your developers flexible features for project management that adapts to any team, project, and workflow—all alongside your code."
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
            image: image_path("modules/site/social-cards/issues-social.jpg"),
          },
        }
      )
    else
      render "site/features/issues/index"
    end
  end
end
