# typed: true
# frozen_string_literal: true

module GitHub
  # Rack middleware to setup/reset a global context for each request.
  # Sets up the GitHub request context and the Audit context for audit logging.
  class ContextMiddleware
    def initialize(app)
      @app = app
    end

    def call(env)
      GitHub.context = ::Context.new
      Audit.context = ::Context.new
      SensitiveData.context = SensitiveData::Context.new
      @app.call(env)
    end
  end
end
