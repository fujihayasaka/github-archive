# typed: true
# frozen_string_literal: true

module Api::Limiters::TwirpHelpers
  extend ActiveSupport::Concern

  class_methods do
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

    def twirp_elapsed_time_by_client_vnext_enabled?(request)
      twirp_request?(request) && GitHub.flipper[:twirp_elapsed_time_by_client_vnext].enabled?
    end
  end
end
