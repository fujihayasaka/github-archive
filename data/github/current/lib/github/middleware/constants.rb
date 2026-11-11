# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware

    # Public: Commonly used HTTP constants as frozen strings.
    module Constants
      APPLICATION_JSON       = "application/json".freeze
      CONTENT_LENGTH         = "Content-Length".freeze
      CONTENT_TYPE           = "Content-Type".freeze
      EMPTY_BODY             = ["".freeze].freeze
      GH_LIMITED_BY          = "GH-Limited-By".freeze
      GH_LIMITED_GROUP       = "GH-Limited-Group".freeze
      HTTP_X_FORWARDED_HOST  = "HTTP_X_FORWARDED_HOST".freeze
      HTTP_ACCEPT            = "HTTP_ACCEPT".freeze
      HTTP_DNT               = "HTTP_DNT".freeze
      HTTP_REFERER           = "HTTP_REFERER".freeze
      HTTP_USER_AGENT        = "HTTP_USER_AGENT".freeze
      PATH_INFO              = "PATH_INFO".freeze
      QUERY_STRING           = "QUERY_STRING".freeze
      REQUEST_METHOD         = "REQUEST_METHOD".freeze
      RETRY_AFTER            = "Retry-After".freeze
      TEXT_HTML              = "text/html".freeze
      TEXT_PLAIN             = "text/plain".freeze
    end
  end
end
