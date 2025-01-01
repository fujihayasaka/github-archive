# typed: true
# frozen_string_literal: true

module Notifyd
  class MessageHeaders
    MAPPINGS = {
      # Original GitHub's request ID
      "request_id" => "gh-request-id",
      # GitHub's environment
      "env" => "gh-env",
      # Name of the dynamic lab, if present
      "lab_name" => "gh-dynamic-lab-name",

      # Where this message was sent in the first place
      "published_to" => "notifyd-message-published-to",
      # Who sent the message
      "producer" => "notifyd-message-producer",

      # Reuse HTTP headers
      "content_length" => "content-length",
      "content_encoding" => "content-encoding",

      # Tenant context
      "tenant_slug" => "X-GitHub-Tenant",
      "tenant_id" => "X-GitHub-Tenant-ID",
    }

    def initialize
      @hash = {}
    end

    def []=(key, value)
      @hash[key] = value
    end

    # Get a Hash<String, String> (keys and values as strings) with all the keys their final names
    # nil values are removed
    def to_h
      @hash.compact
        .transform_keys { |key| map_key(key) }
        .transform_values(&:to_s)
    end
    alias_method :to_hash, :to_h

    def merge!(other)
      @hash.merge!(other)
    end

    def with_telemetry(context: GitHub.context)
      self[:request_id] = context[:request_id] if context

      self
    end

    def with_github_env(github: GitHub)
      self[:env] = github.deployed_to
      self[:lab_name] = github.dynamic_lab_name if github.dynamic_lab?
      self
    end

    def with_tenant_context(current_tenant: GitHub::CurrentTenant)
      tenant = current_tenant.get.presence
      return self unless tenant

      self[:tenant_slug] = tenant.slug
      self[:tenant_id] = tenant.id.to_s

      self
    end

    private

    def map_key(key)
      MAPPINGS.fetch(key.to_s) { |k| k }
    end
  end
end
