# typed: true
# frozen_string_literal: true

module Configurable
  module VscodePrivateMarketplaceUrl
    extend T::Helpers
    extend Configurable::Async

    requires_ancestor { Object }
    requires_ancestor { Configurable }

    KEY = "vscode_private_marketplace_url"
    UPDATE_INSTRUMENTATION_KEY = "update_vscode_private_marketplace_url"
    ENTERPRISE_OWNER_REQUIRED_ERROR = "VSCode private marketplace URL can only be set by enterprise owner."
    UNSUPPORTED_ENTERPRISE_ERROR = "Enterprise does not support setting VSCode private marketplace URL."
    INVALID_URL_ERROR = "Invalid URL. The URL should be in the form https://&lt;private marketplace container host name&gt;/api/v1"

    class VscodePrivateMarketplaceUrlError < StandardError; end

    # Public: Set the VS Code private marketplace URL.
    #
    # Returns nothing.
    def update_vscode_private_marketplace_url(url, actor:)
      unless eligible_for_vscode_private_marketplace?
        raise VscodePrivateMarketplaceUrlError.new UNSUPPORTED_ENTERPRISE_ERROR
      end

      if self.is_a?(Business)
        unless self.owner?(actor)
          raise VscodePrivateMarketplaceUrlError.new ENTERPRISE_OWNER_REQUIRED_ERROR
        end
      end

      unless VscodePrivateMarketplaceUrl.valid_url?(url)
        raise VscodePrivateMarketplaceUrlError.new INVALID_URL_ERROR
      end

      return unless config.set!(KEY, url, actor)

      instrument_vscode_private_marketplace_url(url: url, actor: actor)
    end

    # Public: Resets the VS Code private marketplace URL to unset.
    #
    # Returns nothing.
    def reset_vscode_private_marketplace_url(actor:)
      config.delete(KEY, actor)
      instrument_vscode_private_marketplace_url(url: nil, actor: actor)
    end

    # Public: Get the VS Code private marketplace URL.
    #
    # Returns a String URL or nil if not set.
    def vscode_private_marketplace_url
      config.get(KEY).presence
    end
    async_configurable :vscode_private_marketplace_url

    # Public: Has a custom VS Code private marketplace URL been set?
    #
    # Returns a Boolean.
    def vscode_private_marketplace_url?
      !vscode_private_marketplace_url.nil?
    end

    # Public: Is this feature enabled for the business?
    #
    # Returns a Boolean.
    def eligible_for_vscode_private_marketplace?
      return false unless self.is_a?(Business)
      return false unless FeatureFlag.vexi.enabled?(:vscode_private_marketplace_setting, self, default: false)

      true
    end

    # Private: Validate the given URL starts with http:// or https:// and is well-formed and valid.
    # The URL must end with /api/v1 too.
    def self.valid_url?(url)
      uri = URI.parse(url)
      return false unless uri.is_a?(URI::HTTP) && !uri.host.nil?
      return false unless uri.path&.end_with?("/api/v1")
      true
    rescue URI::InvalidURIError
      false
    end

    # Private: Instrument VS Code private marketplace URL update event.
    #
    # Returns nothing.
    def instrument_vscode_private_marketplace_url(url:, actor:)
      payload = {
        actor: actor,
        url: url,
        business: self
      }

      GitHub.instrument(UPDATE_INSTRUMENTATION_KEY, payload)
    end
  end
end
