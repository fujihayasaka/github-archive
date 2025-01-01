# typed: true
# frozen_string_literal: true

class Api::Desktop < Api::App
  # Generates the info of the Desktop channel for Alive (both the name and its
  # signed version) for the current user.
  get "/desktop_internal/alive-channel", operation_id: :internal do
    @route_owner = "@github/web-systems-reviewers"

    control_access :desktop_user,
      resource: current_user,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    channel_name = GitHub::WebSocket::Channels.desktop_user(current_user)

    signed_channel = GitHub::WebSocket.signed_channel(channel_name)
    deliver_raw({ signed_channel: signed_channel, channel_name: channel_name })
  end

  get "/desktop/avatar-token", operation_id: "desktop/avatar-token" do
    @route_owner = "@github/object-storage-reviewers"
    deliver_error! 404, message: "Not Found" unless GitHub.multi_tenant_enterprise?

    tenant = request.env["HTTP_X_GITHUB_TENANT"]
    unless tenant
      deliver_error!(400, message: "request is missing required tenant data")
    end

    business = Business.find_by(slug: tenant)
    deliver_error! 404, message: "Not found" unless business

    control_access :check_enterprise_managed_business_access,
      resource: business,
      allow_integrations: false,
      allow_user_via_granular_actor: false

    avatar_token = PrimaryAvatar.generate_token_for(tenant, "/u/e")
    deliver :avatar_token, avatar_token
  end
end
