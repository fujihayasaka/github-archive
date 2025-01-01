# typed: true
# frozen_string_literal: true

# This middleware is used to ensure that the GH::Context is enabled for the duration of the request.
# This is necessary because the GH::Context is disabled by default in production, and we want to ensure
# that it is enabled for all API requests.
class Api::Middleware::Context
  def initialize(app)
    @app = app
  end

  def call(env)
    GH::Context.enabled { @app.call(env) }
  end
end
