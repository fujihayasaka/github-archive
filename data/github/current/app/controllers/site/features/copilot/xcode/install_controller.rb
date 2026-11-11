# typed: true
# frozen_string_literal: true

class Site::Features::Copilot::Xcode::InstallController < Site::Features::BaseController
  # Honor the user's GitHub color mode preference (which may itself follow system).
  skip_before_action :disable_color_modes

  before_action :add_csp_exceptions, only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    only: [:index]

  TITLE = "Install GitHub Copilot for Xcode"
  DESCRIPTION = "Install GitHub Copilot for Xcode to bring AI-assisted coding to your iOS and macOS projects."

  CSP_EXCEPTIONS = {}

  stylesheet_bundle "landing-pages"

  def index
    render_react_app(
      app_name: "landing-pages",
      title: TITLE,
      page_data: {
        description: DESCRIPTION,
        richweb: {
          description: DESCRIPTION,
          title: TITLE,
          url: request.original_url,
        },
        revenue_play: "Platform",
        hide_header_content: true,
      },
      custom_tags: ["controller:#{controller_path}", "action:#{action_name}"],
    )
  end
end
