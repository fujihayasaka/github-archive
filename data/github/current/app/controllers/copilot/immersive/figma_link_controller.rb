# typed: true
# frozen_string_literal: true

class Copilot::Immersive::FigmaLinkController < ApplicationController
  depends_on_clusters(
    ApplicationRecord::Mysql1,
    ApplicationRecord::Copilot,
    ApplicationRecord::IamAbilities,
    only: [:show]
  )

  def show
    return head :not_found unless current_user.present?
    return head :not_found unless figma_enabled?
    return head :not_found unless figma_url

    server_config = CopilotMcp::Query.find_mcp_server_config_by_user_and_name(user: current_user, name: "figma")
    return head :forbidden unless server_config && server_config.access_token

    figma_client = Figma::Client.new(server_config.access_token, use_bearer_token: true)
    figma_file = figma_client.get_file(T.must(figma_url))

    render json: figma_payload(figma_file)

  rescue ::Figma::APIError => e
    if e.forbidden
      head :forbidden
    else
      Rails.logger.error("Failed to fetch Figma file: #{e}")
      head :not_found
    end
  end

  private

  def figma_payload(file)
    {
      type: "figma",
      title: file.name,
      id: file.key,
      url: figma_url,
      thumbnailUrl: file.thumbnail_url,
      fullImageUrl: file.full_image_url,
    }
  end

  ALLOWED_FIGMA_HOSTS = ["figma.com", "www.figma.com"].freeze

  sig { returns(T.nilable(String)) }
  memoize def figma_url
    return nil unless params[:item_url]
    item_url = params[:item_url].strip
    item_url = "https://#{item_url}" unless item_url.start_with?("http")

    uri = URI.parse(T.must(item_url))
    return nil unless ALLOWED_FIGMA_HOSTS.include?(uri.host)
    item_url
  end

  def figma_enabled?
    current_user.feature_flag_enabled?(:copilot_immersive_figma_integration, default: false)
  end

  def target_for_conditional_access
    current_user
  end

  def resource_for_conditional_access
    # this is an external resource, so no CAP checks are needed
    :no_resource_for_conditional_access # rubocop:todo GitHub/SpecifyResourceForConditionalAccess
  end
end
