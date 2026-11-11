# typed: true
# frozen_string_literal: true

# In development, we want to treat all requests that
# come over the tailnet as local requests; that means we don't need
# to bypass the basic auth for public codespaces. We _only_ do this
# when in development mode; in production, we want to ensure that
# requests are coming from the expected IPs and not just any
# old IP address that happens to be in the CGNAT range.

if Rails.env.development?
  module TailnetLocalRequests
    # Tailscale's CGNAT range: 100.64.0.0 – 100.127.255.255
    # If you have additional subnets routed over Tailscale, add them here
    TAILNET_CIDRS = [
      IPAddr.new("100.64.0.0/10")
    ].freeze

    def local?
      # In development, we consider requests coming across the Tailnet to be local.
      super || tailnet_local_request?
    end

    def tailnet_local_request?
      request = T.cast(self, ActionDispatch::Request)
      ip = IPAddr.new(request.remote_ip)
      TAILNET_CIDRS.any? { |cidr| cidr.include?(ip) }
    rescue IPAddr::InvalidAddressError
      false
    end
  end

  ActionDispatch::Request.prepend(TailnetLocalRequests)
end
