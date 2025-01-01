# typed: true
# frozen_string_literal: true

class Site::Features::IssuesController < Site::Features::BaseController

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
  layout "site_features"

  # Styles
  stylesheet_bundle "landing-pages", "feature-shared-fp24", "feature-issues-fp24", only: [:index]

  def index
    page_meta = {
      title: "GitHub Issues · Project planning for developers",
      description: "Give your developers flexible features for project management that adapts to any team, project, and workflow—all alongside your code."
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
          image: image_path("modules/site/social-cards/issues-social.jpg"),
        },
      }
    )
  end
end
