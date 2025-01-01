# typed: true
# frozen_string_literal: true

require "syslog"

module Audit
  module Syslog
    SYSLOG_EVENT_ITEMS = [
      :actor_id,
      :actor,
      :oauth_app_id,
      :action,
      :user_id,
      :user,
      :repo_id,
      :repo,
      :actor_ip,
      :created_at,
      :from,
      :note,
      :org,
      :org_id,
      :data,
    ].freeze

    SYSLOG_OPTIONS = ::Syslog::LOG_CONS | ::Syslog::LOG_NDELAY
    SYSLOG_FACILITY = ::Syslog::LOG_LOCAL7
    SYSLOG_IDENT = "github_audit".freeze

    def self.service
      ::Audit::Service.new logger: ::Audit::Syslog::Logger.new
    end

    class Logger
      # Public: Splits non-indexed Audit payload data into a separate 'data'
      # key.
      #
      #   split_payload(:actor_id => 1, :foo => 'bar')
      #   # {:actor_id => 1, :data => {:foo => 'bar'}}
      #
      # Returns a Hash.
      def split_payload(payload)
        data = {}
        payload.each_key do |key|
          next if SYSLOG_EVENT_ITEMS.include?(key.to_sym)
          data[key] = payload.delete(key)
        end
        payload[:data] = data
        payload
      end

      def initialize
        open_syslog unless ::Syslog.opened?
      end

      # Internal: Formats the message into a string for syslog
      #
      # payload - The Hash of data that is sent syslog.
      #
      # Returns the stringified payload.
      def format_event(payload)
        split_payload(payload).to_json
      end

      # Internal: Logs audit entry to Syslog
      #
      # payload - The Hash of data that is sent over as a string.
      #
      # Returns the Syslog instance.
      def perform(payload)
        if ::Syslog.opened?
          reopen_syslog
        else
          open_syslog
        end
        ::Syslog.log(::Syslog::LOG_INFO, "%s", format_event(payload))
      end

      private

      def reopen_syslog
        ::Syslog.reopen(SYSLOG_IDENT, SYSLOG_OPTIONS, SYSLOG_FACILITY)
      end

      def open_syslog
        ::Syslog.open(SYSLOG_IDENT, SYSLOG_OPTIONS, SYSLOG_FACILITY)
      end
    end
  end
end
