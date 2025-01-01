# typed: true
# frozen_string_literal: true

module CopilotSpaces::RouteHelper
  # Checks if the request path corresponds to any copilot spaces routes
  def self.custom_copilots_immersive_route?(request, params)
    url_helpers = Rails.application.routes.url_helpers
    request.path == url_helpers.copilot_spaces_list_path ||
      (params[:space_id] && request.path == url_helpers.copilot_spaces_show_path(space_id: params[:space_id])) ||
      (params[:owner] && params[:number] && request.path == url_helpers.copilot_spaces_show_by_number_path(owner: params[:owner], number: params[:number]))
  end
end
