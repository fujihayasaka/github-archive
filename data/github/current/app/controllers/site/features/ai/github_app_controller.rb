# typed: true
# frozen_string_literal: true

class Site::Features::Ai::GitHubAppController < Site::Features::BaseController
  before_action :check_feature_flag_enabled
  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  TITLE = "GitHub Copilot app"
  DESCRIPTION = "The GitHub Copilot app is the only desktop experience for agent-driven development built natively on GitHub for macOS, Windows, and Linux."

  CSP_EXCEPTIONS = {}

  stylesheet_bundle "landing-pages"

  def index
    render_react_app(
      app_name: "landing-pages",
      title: TITLE,
      page_data: {
        class: "header-white",
        marketing_page_theme: "light",
        marketing_footer_theme: "light",
        description: DESCRIPTION,
        richweb: {
          description: DESCRIPTION,
          image: image_path("modules/site/social-cards/github-app-ga.jpg"),
          title: TITLE,
          url: request.original_url,
        },
        revenue_play: "Platform",
      },
      custom_tags: ["controller:#{controller_path}", "action:#{action_name}"],
      payload: {},
    )
  end

  private

  def check_feature_flag_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:site_github_app_ga_page, current_user, default: false)
  end
end
