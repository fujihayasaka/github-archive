# typed: true
# frozen_string_literal: true

# Eagerly load the generated PolicyConfigAPI proto types so that callers
# (including tapioca DSL generation) can reference the constants without
# touching the autoloaded client first.
require "monolith-twirp-packagefirewall-package_firewall"

module PackageFirewall
  module Twirp
    autoload :PackageFirewallClient, "package_firewall/twirp/package_firewall_client"
    autoload :PackageFirewallConnection, "package_firewall/twirp/package_firewall_connection"

    # Base class for all PackageFirewall Twirp client errors. Carries the
    # original twirp_error and a human-readable msg for callers that want to
    # surface validation messages from the server.
    class BaseError < StandardError
      attr_accessor :msg
      attr_accessor :twirp_error
    end

    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end
    class InvalidArgumentError < BaseError; end
    class NotFoundError < BaseError; end
  end
end
