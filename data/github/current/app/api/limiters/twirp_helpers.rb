# typed: true
# frozen_string_literal: true

module Api::Limiters::TwirpHelpers
  extend ActiveSupport::Concern

  class_methods do
    UNKNOWN_CLIENT_NAME = "unknown"

    # Public: Extract the Twirp path from the incoming request.
    #
    # request - Rack::Request instance.
    #
    # Returns String if Twirp path is present, false otherwise.
    def twirp_path(request)
      if request.path_info =~ ::Api::Internal::Twirp::PATH_REGEX
        request.path_info
      end
    end

    # Public: Extract the rpc partion of the path from the incoming request.
    #
    # request - Rack::Request instance.
    #
    # Returns String if Twirp path is present, false otherwise.
    # Example: "/api/internal/twirp/github.example.v1/HelloWord" returns github.example.v1/HelloWord
    def twirp_rpc_path(request)
      if match = ::Api::Internal::Twirp::PATH_REGEX.match(request.path_info)
        if match.length == 2
          match[1]
        end
      end
    end

    # Public: Determine if the incoming request is for a Twirp endpoint,
    # which always use POST requests.
    #
    # request - Rack::Request instance.
    #
    # Returns true if Twirp request, false otherwise.
    def twirp_request?(request)
      return false if request.request_method != "POST"
      !twirp_path(request).nil?
    end

    def twirp_client_name(request)
      Api::Internal::Twirp.client_name_from_header(request)
    end

    def twirp_request_count_by_client_and_path_enabled?(request)
      twirp_request?(request) && FeatureFlag.vexi.enabled?(:twirp_request_count_by_client_and_path, default: false)
    end

    def resolve_twirp_client_name(request)
      twirp_client_name(request) || UNKNOWN_CLIENT_NAME
    end

    def twirp_client_name_per_request(request)
      return request.env[:twirp_client_name] if request.env[:twirp_client_name].present?

      request.env[:twirp_client_name] = resolve_twirp_client_name(request)
    end
  end
end
