# typed: true
# frozen_string_literal: true

require "faraday"

# Manages consul KV entries to stop and start workers on a given worker host.
# Worker hosts read the KV values and stop or start worker processes accordingly.
module Resqued
  module WorkerManagement
    KV_PREFIX = "github/resqued/stop_workers"
    PER_APP_ROLE_LIMIT = 5
    MANAGED_SITES = %w[ ac4-iad ash1-iad va3-iad ]

    def self.stop_workers(hostname:, user:, room_id:, client: ConsulClient.new)
      hostname = Hostname.new(hostname)

      unless MANAGED_SITES.include?(hostname.site)
        raise ArgumentError.new("Invalid site: #{hostname.site.inspect}, only managing #{MANAGED_SITES.join(", ")}")
      end

      stopped_count = client.kv_list(dc: hostname.site, prefix: KV_PREFIX).count { |h| h.start_with?(hostname.app_role) }

      if stopped_count >= PER_APP_ROLE_LIMIT
        raise ArgumentError.new(
          "Workers are already stopped on #{stopped_count} hosts in #{hostname.site}, refusing to stop more.")
      end

      # only write to the consul where the server lives: this is the only place it needs to exist.
      client.kv_put(
        dc: hostname.site,
        key: "#{KV_PREFIX}/#{hostname}",
        value: { stopped_at: Time.now.to_i, user: user, room_id: room_id }.to_json
      )
    end

    def self.start_workers(hostname:, client: ConsulClient.new)
      hostname = Hostname.new(hostname)

      client.kv_delete(dc: hostname.site, key: "#{KV_PREFIX}/#{hostname}")
    end

    def self.stopped_workers(client: ConsulClient.new)
      MANAGED_SITES.flat_map do |site|
        client.kv_list(dc: site, prefix: KV_PREFIX).sort.map do |key|
          data = JSON.parse(
            Base64.decode64(
              client.kv_get(dc: site, key: key).first["Value"]))

          {
            hostname: key.split("/").last,
            stopped_at: Time.at(data["stopped_at"]).utc.iso8601,
            user: data["user"],
            room_id: data["room_id"],
          }
        end
      end
    end

    class Hostname
      HOST_PATTERN = /\A(?<app_role>[\w-]+)-\w+\.(?<site>[\w-]+)\.github.net\Z/

      def initialize(hostname)
        @raw = hostname

        matchdata = HOST_PATTERN.match(@raw)
        unless matchdata
          raise ArgumentError.new("Invalid hostname: #{hostname.inspect}")
        end

        @app_role = matchdata[:app_role]
        @site = matchdata[:site]
      end

      def app_role
        @app_role
      end

      def site
        @site
      end

      def to_s
        @raw
      end
    end

    class ConsulClient
      def initialize(host: nil)
        @host = host || ENV.fetch("KUBE_NODE_HOSTNAME", "127.0.0.1") + ":8500"
      end

      def kv_list(dc:, prefix:)
        response = conn.get("/v1/kv/#{prefix}", dc: dc, keys: true)
        return [] if response.status == 404

        JSON.parse(response.body)
      end

      def kv_get(dc:, key:)
        JSON.parse(conn.get("/v1/kv/#{key}?dc=#{dc}").body)
      end

      def kv_put(dc:, key:, value:)
        conn.put("/v1/kv/#{key}?dc=#{dc}", value)
      end

      def kv_delete(dc:, key:)
        conn.delete("/v1/kv/#{key}?dc=#{dc}")
      end

      private

      def get(path)
        "http://#{@host}/v1/#{path}"
      end

      def conn
        @conn ||= Faraday.new("http://#{@host}") # rubocop:disable GitHub/RequireExplicitInternalOrExternalFaradayClientWrapper
      end
    end
  end
end
