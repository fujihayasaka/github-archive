# typed: true
# frozen_string_literal: true

# Base class for all GHEC Enterprise account API actions
module Api
  module Enterprise
    class App < Api::App
      before do
        update_enterprise_links
      end

      sig { void }
      def update_enterprise_links
        url = request.scheme + "://"
        url << request.host

        if request.scheme == "https" && request.port != 443 ||
            request.scheme == "http" && request.port != 80
          url << ":#{request.port}"
        end

        if prefix = env[GitHub::Routers::Api::API_PATH]
          url << prefix
        end

        url << env[GitHub::Routers::Api::ORIGINAL_PATH_INFO]

        @links = PiLinkCollection.new url, env["rack.request.query_hash"]
      end
    end
  end
end
