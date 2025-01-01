# frozen_string_literal: true

require "github/ldap"

# Patches for time out long searches
module GitHub::Ldap::MemberSearch
  module WithTimeout
    # inherit from SyncError so TeamSync can handle the exception
    class SearchTimeoutError < ::GitHub::LDAP::TeamSync::SyncError
      def initialize(msg, group:)
        super(msg)
        @group = group
      end

      # This method is required by TeamSync when reporting exceptions
      def payload
        { group: @group }
      end
    end

    DEFAULT_TIMEOUT_SEC = ENV.fetch("ENTERPRISE_LDAP_TEAM_SYNC_MEMBER_SEARCH_TIMEOUT", 600).to_i # 10min

    def perform(group, timeout_sec: DEFAULT_TIMEOUT_SEC)
      GitHub::Authentication::LDAPSync.logger.with_named_tags("code.namespace" => "GitHub::LDAP::MemberSearch::WithTimeout", "code.function" => "perform", "ldap.dn" => group.dn, "ldap.timeout_sec" => timeout_sec, "net.peer.name" => remote_address, "code.op" => "member_search") do
        GitHub::Authentication::LDAPSync.logger.info("Team sync: member search (with timeout)")

        Timeout.timeout(timeout_sec) do
          super(group)
        end
      rescue Timeout::Error => e
        GitHub::Authentication::LDAPSync.logger.error("Team sync: member search timeout error", "exception.message" => e.message)
        raise SearchTimeoutError.new(
          "Team member search timed out after #{timeout_sec}sec",
          group: group.dn
        )
      end
    end

    def remote_address
      conn = GitHub.auth.strategy
        .connection.instance_variable_get(:@open_connection)

      return unless conn

      conn.socket.remote_address.ip_unpack.join(":")
    rescue # rubocop:todo Lint/RescueException
      # we just want to give up and not throw any errors
    end
  end

  enabled = ENV["ENTERPRISE_LDAP_TEAM_SYNC_MEMBER_SEARCH_TIMEOUT_ENABLED"] == "1" || Rails.env.test?

  if enabled
    class ActiveDirectory
      prepend WithTimeout
    end

    class Recursive
      prepend WithTimeout
    end

    class Classic
      prepend WithTimeout
    end
  end
end
