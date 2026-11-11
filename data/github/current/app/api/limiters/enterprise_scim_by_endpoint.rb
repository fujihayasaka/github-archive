# typed: true
# frozen_string_literal: true

module Api
  module Limiters
    # This limiter is used to limit the number of requests to SCIM endpoints
    # for a given enterprise.  The limiter is keyed by the HTTP method name,
    # enterprise slug or id, and the type of SCIM endpoint (Users or Groups).
    class EnterpriseSCIMByEndpoint < GitHub::Limiters::MemcachedWindow
      # view modification and changes to regex at: https://rubular.com/r/rqUMu0hQkoChdU
      ENTERPRISE_SCIM_ENDPOINT_REGEX = /\/scim\/v2\/enterprises\/([\w-]+)\/([Users|Groups]+)/

      include GitHub::Middleware::Constants

      def initialize(max:)
        super("enterprise-scim-by-path", limit: max)
      end

      def record_start(request)
        return OK if GitHub.enterprise?
        return OK if request_method(request) == "GET"

        enterprise_slug_or_id, _ = business_slug_from_path(request)

        return OK unless enterprise_slug_or_id

        increment_counter(request)
      end

      protected

      def at_limit?(request)
        return false if GitHub.enterprise?
        return false if request_method(request) == "GET"

        enterprise_slug_or_id, _ = business_slug_from_path(request)

        return false unless enterprise_slug_or_id
        super
      end

      def key(request)
        enterprise_slug_or_id, users_or_groups = business_slug_from_path(request)
        return super unless enterprise_slug_or_id

        "#{request_method(request)}:#{enterprise_slug_or_id}:#{users_or_groups}"
      end

      def cost(request)
        case request.request_method
        # Add cost for PATCH requests to SCIM endpoints, cost will limit
        # the number of requests to SCIM endpoints for a given enterprise and
        # request method type.
        when "PATCH"
          5
        else
          1
        end
      end

      private

      def request_method(request)
        request.env["REQUEST_METHOD"]
      end

      def business_slug_from_path(request)
        if ENTERPRISE_SCIM_ENDPOINT_REGEX.match(request.path_info)
          # regex will get the business slug or id
          enterprise_slug_or_id = $1
          users_or_groups = $2

          return [nil, nil] if enterprise_slug_or_id.blank?

          [enterprise_slug_or_id, users_or_groups]
        else
          [nil, nil]
        end
      end
    end
  end
end
