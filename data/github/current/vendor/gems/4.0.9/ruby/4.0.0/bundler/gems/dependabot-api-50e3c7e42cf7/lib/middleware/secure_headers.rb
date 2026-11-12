# frozen_string_literal: true

module Middleware
  class SecureHeaders
    def initialize(app)
      @app = app
      @headers = {
        "Strict-Transport-Security" => "max-age=31557600; includeSubDomains; "\
                                       "preload",
      }
    end

    def call(env)
      @app.call(env).tap do |_, headers, _|
        @headers.each do |key, value|
          headers[key] ||= value
        end
      end
    end
  end
end
