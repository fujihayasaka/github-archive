# typed: true
# frozen_string_literal: true

require "monolith-twirp-packagefirewall-package_firewall"

module Api::Internal::Twirp::Packagefirewall
  module PackageFirewall
    module V0
      class PackageFirewallAPIHandler < Api::Internal::Twirp::Handler
        allow_access_for :client, allowed_clients: ["package_firewall"]
        handles_service MonolithTwirp::Packagefirewall::PackageFirewall::V0::PackageFirewallAPIService

        resolve_tenant_context only: [:get_enterprise_context] do |req, _env|
          Business.find_by(slug: req.enterprise_slug)
        end

        def get_enterprise_context(req, _env)
          return Twirp::Error.invalid_argument("must be non-empty", argument: "enterprise_slug") if req.enterprise_slug.blank?
          return Twirp::Error.invalid_argument("must be non-zero", argument: "actor_id") if req.actor_id.zero?

          business = Business.find_by(slug: req.enterprise_slug)
          return Twirp::Error.not_found("enterprise not found") if business.nil?

          user = User.find_by(id: req.actor_id)
          return Twirp::Error.not_found("actor not found") if user.nil?

          return Twirp::Error.permission_denied("actor is not an enterprise member") unless business.member?(user)

          { enterprise_id: business.id }
        end
      end
    end
  end
end
