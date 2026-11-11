# typed: true
# frozen_string_literal: true

class Copilot::Xcode::InstallController < ApplicationController
  stylesheet_bundle :"copilot-for-xcode-install"

  TITLE = "Install GitHub Copilot for Xcode"
  DESCRIPTION = "Install GitHub Copilot for Xcode to bring AI-assisted coding to your iOS and macOS projects."

  def index
    render_react_app(
      app_name: "copilot-for-xcode-install",
      title: TITLE,
      data_router_enabled: true,
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

  private

  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
