# typed: strict
# frozen_string_literal: true

class Copilot::AppController < ApplicationController
  APP_DEEP_LINK_SCHEME = "ghapp://"

  TITLE = "Open GitHub Copilot"
  DESCRIPTION = "Open the GitHub Copilot app from GitHub."
  SOCIAL_CARD_IMAGE = "modules/site/social-cards/copilot-app-launcher.png"

  sig { void }
  def index
    open = app_deep_link
    unless valid_app_deep_link?(open)
      render_404
      return
    end

    render_react_app(
      app_name: "copilot-app-launcher",
      title: TITLE,
      data_router_enabled: true,
      payload: {
        open: open,
      },
      page_data: {
        description: DESCRIPTION,
        richweb: {
          description: DESCRIPTION,
          image: image_path(SOCIAL_CARD_IMAGE),
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

  sig { returns(T.nilable(String)) }
  def app_deep_link
    open = params[:open]
    return unless open.is_a?(String)

    open.presence
  end

  sig { params(open: T.nilable(String)).returns(T::Boolean) }
  def valid_app_deep_link?(open)
    open.nil? || open.start_with?(APP_DEEP_LINK_SCHEME)
  end

  sig { returns(Symbol) }
  def resource_for_conditional_access
    :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end
end
