# typed: true
# frozen_string_literal: true

module GitHub::Goomba::Async::AssetLoaders
  class AssetLoader
    GUID_REGEX = /(\{){0,1}[0-9a-fA-F]{8}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{4}\-[0-9a-fA-F]{12}(\}){0,1}/

    def initialize(current_user)
      @current_user = current_user
    end

    def load_node_asset(node)
      nil
    end

    def asset_uri(node, caller_name: "load_node_asset")
      begin
        Addressable::URI.parse(node["src"])
      rescue Addressable::URI::InvalidURIError => error
        log_error(error, "code.function": caller_name, "code.namespace": self.class.name)
        GitHub.dogstats.increment("goomba.secure_assets_presign.error.count", tags: build_metric_tags.append("error_class:#{error.class.name}"))
        nil
      end
    end

    def is_uri_valid?(uri)
      uri.present? && uri.host.present? && is_github_url?(uri.host) && uri.request_uri != "/"
    end

    def log_error(error, attributes = {})
      log = {
        "exception.message": error.message,
        "exception.type": error.class.name,
        "gh.actor.authenticated": @current_user.present?,
        "gh.actor.id": @current_user&.id,
      }

      log.merge!(attributes)
      GitHub.logger.error("exception", log)
    end

    def build_metric_tags
      ["user_logged_in:#{@current_user ? "true" : "false"}"]
    end

    private

    def is_github_url?(host)
      GitHub.image_proxy_host_allowlist.any? do |test|
        # We call sub(/:.*/, "") because sometimes in Codespaces the port is included in the host_name and the host
        # coming from an Addressable::URI will not have the port included.
        test.is_a?(String) ? host == test.sub(/:.*/, "") : test.match(host)
      end
    end
  end
end
