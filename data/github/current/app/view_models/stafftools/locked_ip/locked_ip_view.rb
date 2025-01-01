# typed: true
# frozen_string_literal: true

module Stafftools
  module LockedIp
    class LockedIpView < ViewModel # rubocop:todo ViewComponent/NoMoreViewModels

      attr_reader :ip_address

      def page_title
        "Locked IPs"
      end

      def at_auth_limit?
        AuthenticationLimit.at_any?(ip: ip_address, web_ip: ip_address)
      end

      def expiration
        AuthenticationLimit.longest_expiration(ip: ip_address, web_ip: ip_address)
      end

      def whitelisted?
        return @whitelisted if defined?(@whitelisted)
        @whitelisted = AuthenticationLimitAllowlistEntry.allowed?("ip", ip_address)
      end

      def whitelist_entry
        return @whitelist_entry if defined?(@whitelist_entry)
        @whitelist_entry = AuthenticationLimitAllowlistEntry.find_active("ip", ip_address)
      end
    end
  end
end
