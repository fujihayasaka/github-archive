# typed: true
# frozen_string_literal: true

module GitHub::HTML
  class HttpsFilter < ::HTML::Pipeline::HttpsFilter
    # Public: HTTP url to replace.
    #
    # Returns String.
    def http_url
      GitHub.urls.http_url
    end
  end
end
