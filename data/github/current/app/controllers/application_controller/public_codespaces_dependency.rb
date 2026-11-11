# typed: true
# frozen_string_literal: true

module ApplicationController::PublicCodespacesDependency
  extend T::Helpers
  extend ActiveSupport::Concern

  requires_ancestor { ApplicationController }

  # Layers in some basic authentication when run in a codespace that's
  # forwarding its ports publicly. The password is generated either by script/server
  # or our custom hello-githug extension, and saved to file at tmp/public_port_pw.

  included do
    T.bind(self, T.class_of(ApplicationController))

    if Rails.env.development? && ENV["CODESPACES"]
      before_action :basic_auth_for_public_forwarded_ports
    end
  end

  def basic_auth_for_public_forwarded_ports
    # We never require basic auth for local requests
    return if request.local?

    unless request.headers["HTTP_AUTHORIZATION"]&.start_with?("Basic ")
      if request.host.ends_with?(ENV["GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN"])
        # Next we need to determine if it's a private port running in the browser. We'll check by hitting a route in the
        # monolith and seeing if we get its response.
        client = GitHub::FaradayClient::External.new do |conn|
          conn.adapter Faraday.default_adapter
        end
        redirect_check = client.head("https://#{request.host}/port_visibility_check")

        # 299 indicates we actually hit the route served by the monolith, which means the port must be public and so
        # we should require basic auth.
        return unless redirect_check.status == 299
      end
    end

    authenticate_or_request_with_http_basic("Codespace Previewers", "This preview requires credentials from the codespace owner") do |username, password|
      if ENV["GH_PUBLIC_FORWARDED_CODESPACE_PW"] # Edge case, implies server was stood up with something other than script/server, like bin/rails server
        username == "monalisa" && SecurityUtils.secure_compare(password, ENV["GH_PUBLIC_FORWARDED_CODESPACE_PW"])
      else
        false
      end
    end
  end
end
