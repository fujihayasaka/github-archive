# typed: true
# frozen_string_literal: true
require "uri"

class Api::Middleware::ProgrammaticAccessValidator
  attr_reader :endpoints

  IGNORED_PATHS = %w(
    /applications
    /chunks
    /code
    /embeddings
    /graphql
    /internal/storage
    /internal/twirp
    /lsp
    /symbols
  )

  def initialize(app, endpoints)
    @app = app
    @top_app = get_top_level_app(app)
    @endpoints = endpoints
  end

  def call(env)
    request = Rack::Request.new(env)
    return @app.call(env) unless should_validate_request?(request)

    result = Api::ProgrammaticAccessValidator.new(env, endpoints).validate!
    return @app.call(env) if result.success?
    raise result.exception
  end

  private

  def should_validate_request?(request)
    return false if is_test_app?(@app) || is_test_app?(@top_app)

    path_info = request.path_info
    !IGNORED_PATHS.any? { |ignored_path| path_info.starts_with?(ignored_path) }
  end

  def is_test_app?(app)
    # True for any test class except the one we use to actually test the  middleware
    # ApiMiddlewareProgrammaticAccessValidatorTest::PAVStubApi
    class_name = app.class.name
    class_name.match(/Test/) && !class_name.match(/PAVStubApi/)
  end

  # Taken from route_finder.rb
  def get_top_level_app(app)
    until app.instance_variable_get(:@app).nil?
      app = app.instance_variable_get(:@app)
    end
    app
  end
end
