# typed: true
# frozen_string_literal: true

module GitHub
  module Middleware
    # Handles ActionController::UnknownHttpMethod exceptions, reports them to
    # the Failbot user bucket (as a user error) and returns the appropriate 405
    # error code.
    class UnknownHttpMethod
      def initialize(app)
        @app = app
      end

      def call(env)
        @app.call(env)
      rescue ActionController::UnknownHttpMethod => e
        Failbot.report_user_error(e)
        [405, { "Content-Type" => "text/plain" }, ["Method Not Allowed: #{e}"]]
      end
    end
  end
end
